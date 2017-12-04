//
//  ChatVC.swift
//  TravelApp_2
//
//  Created by Andy on 8/8/17.
//  Copyright © 2017 ahutch. All rights reserved.
//

import UIKit
import Photos
import Firebase
import JSQMessagesViewController
import CryptoSwift

final class ChatVC: JSQMessagesViewController {
    
    var chain: [UInt8]! = []
    var aesKey: [UInt8]! = []
    var hmacKey: [UInt8]! = []
    var iv:[UInt8]! = []
    lazy var storageRef:StorageReference = Storage.storage().reference(forURL: "gs://cryptochat-c765d.appspot.com")
    
    let userDefaults = UserDefaults.standard
    //database references
    lazy var dbRef = Database.database().reference()
    lazy var chatRef: DatabaseReference = self.dbRef.child("chats").child(self.chatId)
    lazy var messagesRef: DatabaseReference = self.dbRef.child("chats").child(self.chatId).child("messages")
    
    //handlers for releasing references
    var dbHandle: DatabaseHandle?
    var typingHandle: DatabaseHandle?
    var messagesHandle: DatabaseHandle?
    var updatedMessageRefHandle: DatabaseHandle?
    
    
    lazy var usersTypingQuery: DatabaseQuery =
        self.chatRef.child("typingIndicator").queryOrderedByValue().queryEqual(toValue: true)
    
    //Both these variables set in prepare method from tripTable
    var username: String!
    var chatId: String!
    var user = Auth.auth().currentUser
    
    private var localTyping = false
    var isTyping: Bool{
        get {
            return localTyping
        }
        set {
            localTyping = newValue
            self.chatRef.child("typingIndicator").child((self.user?.uid)!).setValue(localTyping)
        }
    }
    
    let imageURLNotSetKey = "NOTSET"
    var photoMessageMap = [String: JSQPhotoMediaItem]()
    
    var messages: [JSQMessage] = []
    lazy var outgoingBubbleImageView: JSQMessagesBubbleImage = self.setupOutgoingBubble()
    lazy var incomingBubbleImageView: JSQMessagesBubbleImage = self.setupIncomingBubble()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        chain = userDefaults.object(forKey: chatId + "chain") as? [UInt8]
        aesKey = Array(chain[0..<32])
        hmacKey = Array(chain[32..<64])
        iv = Array(chain[64...])
        checkPermission()
        //defines the 2 required properties for JSQM
        self.senderId = Auth.auth().currentUser?.uid
        self.senderDisplayName = username
        
        collectionView!.collectionViewLayout.incomingAvatarViewSize = CGSize.zero
        collectionView!.collectionViewLayout.outgoingAvatarViewSize = CGSize.zero
        
        self.scrollToBottom(animated: true)
        observeMessages()
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        observeTyping()
        self.scrollToBottom(animated: true)
    }
    
    deinit {
        if let refHandle = messagesHandle {
            messagesRef.removeObserver(withHandle:refHandle)
        }
        if let refHandle = dbHandle {
            dbRef.removeObserver(withHandle:refHandle)
        }
        if let refHandle = typingHandle {
            usersTypingQuery.removeObserver(withHandle:refHandle)
        }
        if let refHandle = updatedMessageRefHandle {
            messagesRef.removeObserver(withHandle: refHandle)
        }
    }
}

extension ChatVC {
    
    func observeMessages(){
        messagesHandle = messagesRef.observe(.childAdded, with: { (snapshot) -> Void in
            let messageData = snapshot.value as! [String:Any]
            
            //text message
            if let id = messageData["senderId"] as? String, let name = messageData["senderName"] as? String, let text = messageData["text"] as? String, text.characters.count > 0 {
                var decodedData: [UInt8] = []
                do {
                    let encryptedData = Data.init(base64Encoded: text)!.bytes
                    decodedData = try AES(key: self.aesKey, blockMode: .CBC(iv: self.iv), padding: .pkcs7).decrypt(encryptedData)
                } catch { }
                let decodedText = String(data: Data(bytes: decodedData), encoding: String.Encoding.utf8) as String!
                self.addMessage(withId: id, name: name, text: decodedText!)
                self.finishReceivingMessage()
            }
            
            //photo message
            else if let id = messageData["senderId"] as? String,
                let photoURL = messageData["photoURL"] as? String {
                if let mediaItem = CustomJSQPhotoMediaItem(maskAsOutgoing: id == self.senderId) {
                    self.addPhotoMessage(withId: id, key: snapshot.key, mediaItem: mediaItem)
                    if photoURL.hasPrefix("gs://") {
                        self.fetchImageDataAtURL(photoURL, forMediaItem: mediaItem, clearsPhotoMessageMapOnSuccessForKey: nil)
                    }
                }
            }
            else {
                print("Error! Could not decode message data", messageData)
            }
            
            //Message change - a la photo finished uploading to server, and url got set
            self.updatedMessageRefHandle = self.messagesRef.observe(.childChanged, with: { (snapshot) in
                let key = snapshot.key
                let messageData = snapshot.value as! Dictionary<String, String>
                
                if let photoURL = messageData["photoURL"] as String! {
                    // The photo has been updated.
                    if let mediaItem = self.photoMessageMap[key] {
                        self.fetchImageDataAtURL(photoURL, forMediaItem: mediaItem as! CustomJSQPhotoMediaItem, clearsPhotoMessageMapOnSuccessForKey: key)
                    }
                }
            })
        })
    }
    
    func observeTyping(){
        chatRef.child("typingIndicator").child((self.user?.uid)!).onDisconnectRemoveValue()
        
        typingHandle = usersTypingQuery.observe(.value, with: {snapshot in
            if snapshot.childrenCount == 1 && self.isTyping {
                return
            }
            
            self.showTypingIndicator = snapshot.childrenCount > 0
            //self.scrollToBottom(animated: true)
        })
    }
    
    override func didPressSend(_ button: UIButton!, withMessageText text: String!, senderId: String!, senderDisplayName: String!, date: Date!) {
        let newMessageRef = messagesRef.childByAutoId()
        let textData = text.data(using: String.Encoding.utf8)?.bytes
        var encryptedData: [UInt8] = []
        do {
            encryptedData = try AES(key: aesKey, blockMode: .CBC(iv: iv), padding: .pkcs7).encrypt(textData!)
        } catch { }
        let messageItem = [
            "senderId": senderId!,
            "senderName": senderDisplayName!,
            "text": (Data(bytes: encryptedData).base64EncodedString()),
            ] as [String : Any]
        
        newMessageRef.setValue(messageItem)
        JSQSystemSoundPlayer.jsq_playMessageSentSound()
        finishSendingMessage()
        isTyping = false
    }
    
    func addMessage(withId id: String, name: String, text: String) {
        if let message = JSQMessage(senderId: id, displayName: name, text: text) {
            messages.append(message)
        }
    }
    
}

extension ChatVC {
    func setupOutgoingBubble() -> JSQMessagesBubbleImage {
        let bubbleImageFactory = JSQMessagesBubbleImageFactory()
        return bubbleImageFactory!.outgoingMessagesBubbleImage(with: UIColor.jsq_messageBubbleBlue())
    }
    
    func setupIncomingBubble() -> JSQMessagesBubbleImage {
        let bubbleImageFactory = JSQMessagesBubbleImageFactory()
        return bubbleImageFactory!.incomingMessagesBubbleImage(with: UIColor.jsq_messageBubbleLightGray())
    }
    
    
}

extension ChatVC {
    //MARK:- Collection Data Source
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, messageDataForItemAt indexPath: IndexPath!) -> JSQMessageData! {
        return messages[indexPath.item]
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return messages.count
    }
    
    //MARK:- Collection delegate methods
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, messageBubbleImageDataForItemAt indexPath: IndexPath!) -> JSQMessageBubbleImageDataSource! {
        let message = messages[indexPath.item] // 1
        if message.senderId == senderId { // 2
            return outgoingBubbleImageView
        } else { // 3
            return incomingBubbleImageView
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = super.collectionView(collectionView, cellForItemAt: indexPath) as! JSQMessagesCollectionViewCell
        let message = messages[indexPath.item]
        
        if message.senderId == senderId {
            cell.textView?.textColor = UIColor.white
        } else {
            cell.textView?.textColor = UIColor.black
        }
        return cell
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView!, avatarImageDataForItemAt indexPath: IndexPath!) -> JSQMessageAvatarImageDataSource! {
        return nil
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView, attributedTextForMessageBubbleTopLabelAt indexPath: IndexPath) -> NSAttributedString? {
        let message = messages[indexPath.item]
        
        if message.senderId == self.senderId {
            return nil
        }
        
        return NSAttributedString(string: message.senderDisplayName)
    }
    
    override func collectionView(_ collectionView: JSQMessagesCollectionView, layout collectionViewLayout: JSQMessagesCollectionViewFlowLayout, heightForMessageBubbleTopLabelAt indexPath: IndexPath) -> CGFloat {
        
        let currentMessage = self.messages[indexPath.item]
        
        if currentMessage.senderId == self.senderId {
            return 0.0
        }
        
        if indexPath.item - 1 > 0 {
            let previousMessage = self.messages[indexPath.item - 1]
            if previousMessage.senderId == currentMessage.senderId {
                return 0.0
            }
        }
        
        return kJSQMessagesCollectionViewCellLabelHeightDefault;
    }
    
    
    
    override func textViewDidChange(_ textView: UITextView) {
        super.textViewDidChange(textView)
        isTyping = textView.text != ""
    }
}

extension ChatVC {
    
    func sendPhotoMessage() -> String? {
        let itemRef = messagesRef.childByAutoId()
        let messageItem = [
            "photoURL": imageURLNotSetKey,
            "senderId": senderId!,
            ]
        itemRef.setValue(messageItem)
        JSQSystemSoundPlayer.jsq_playMessageSentSound()
        finishSendingMessage()
        return itemRef.key
    }
    
    func addPhotoMessage(withId id: String, key: String, mediaItem: JSQPhotoMediaItem) {
        if let message = JSQMessage(senderId: id, displayName: "", media: mediaItem) {
            messages.append(message)
            if (mediaItem.image == nil) {
                photoMessageMap[key] = mediaItem
            }
            collectionView.reloadData()
        }
    }
    
    func fetchImageDataAtURL(_ photoURL: String, forMediaItem mediaItem: CustomJSQPhotoMediaItem, clearsPhotoMessageMapOnSuccessForKey key: String?) {
        let storageRef = Storage.storage().reference(forURL: photoURL)

        storageRef.getData(maxSize: INT64_MAX){ (data, error) in
            if let error = error {
                print("Error downloading image data: \(error)")
                return
            }
            storageRef.getMetadata(completion: { (metadata, metadataErr) in
                if let error = metadataErr {
                    print("Error downloading metadata: \(error)")
                    return
                }
                if (metadata?.contentType == "image/gif") {
                    mediaItem.image = UIImage.gifWithData(data!)
                } else {
                    var decodedData: [UInt8] = []
                    do {
                        let encryptedData = data?.bytes
                        decodedData = try AES(key: self.aesKey, blockMode: .CBC(iv: self.iv), padding: .pkcs7).decrypt(encryptedData!)
                    } catch { }
                    mediaItem.image = UIImage.init(data: Data(bytes:decodedData))
                    mediaItem.mediaViewDisplaySize()
                }
                self.collectionView.reloadData()
                guard key != nil else {
                    return
                }
                self.photoMessageMap.removeValue(forKey: key!)
            })
        }
    }
    
    func setImageURL(_ url: String, forPhotoMessageWithKey key: String) {
        let itemRef = messagesRef.child(key)
        itemRef.updateChildValues(["photoURL": url])
    }
    
    override func didPressAccessoryButton(_ sender: UIButton) {
        let picker = UIImagePickerController()
        picker.delegate = self
        
        let sheet = UIAlertController(title: "Media messages", message: nil, preferredStyle: .actionSheet)
        
        let photoAction = UIAlertAction(title: "Choose photo", style: .default) { (action) in
            picker.sourceType = UIImagePickerControllerSourceType.photoLibrary
            self.present(picker, animated: true, completion:nil)
            
        }
        
        let cameraAction = UIAlertAction(title: "Take photo", style: .default) { (action) in
            if (UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.camera)) {
                picker.sourceType = UIImagePickerControllerSourceType.camera
                self.present(picker, animated: true, completion:nil)
            }
            else{
                print("camera unavailable")
            }
        }
        
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        
        sheet.addAction(photoAction)
        sheet.addAction(cameraAction)
        
        self.present(sheet, animated: true, completion: nil)
        
    }
}

// MARK: Image Picker Delegate
extension ChatVC: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    @objc func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [String : Any]) {
        
        picker.dismiss(animated: true, completion:nil)
        
        if let photoReferenceUrl = info[UIImagePickerControllerReferenceURL] as? URL {
            let assets = PHAsset.fetchAssets(withALAssetURLs: [photoReferenceUrl], options: nil)
            let asset = assets.firstObject
            if let key = sendPhotoMessage() {
                
                asset?.requestContentEditingInput(with: nil, completionHandler: {
                    (contentEditingInput, info) in
                    let imageFileURL = contentEditingInput?.fullSizeImageURL
                    let displayImage = contentEditingInput?.displaySizeImage
                    let data = NSData(contentsOf: imageFileURL!)
                    let metadata = StorageMetadata()
                    let photoData = UIImageJPEGRepresentation(displayImage!, 1.0)
                    let path = "\(self.chatId!)/chat/\((self.user?.uid)!)/\(Int(Date.timeIntervalSinceReferenceDate * 1000))/asset.jpg"
                    
                    let imageData = photoData?.bytes
                    var encryptedData: [UInt8] = []
                    do {
                        encryptedData = try AES(key: self.aesKey, blockMode: .CBC(iv: self.iv), padding: .pkcs7).encrypt(imageData!)
                    } catch { }
                    
                    self.storageRef.child(path).putData(Data(bytes:encryptedData), metadata: nil) { (metadata, error) in
                        if let error = error {
                            print("Error uploading photo: \(error.localizedDescription)")
                            return
                        }
                        self.setImageURL(self.storageRef.child((metadata?.path)!).description, forPhotoMessageWithKey: key)
                    }
                })
            }
        } else {
            let image = info[UIImagePickerControllerOriginalImage] as! UIImage
            if let key = sendPhotoMessage() {
                let imageData = UIImageJPEGRepresentation(image, 1.0)
                let imagePath = (user?.uid)! + "/\(Int(Date.timeIntervalSinceReferenceDate * 1000)).jpg"
                let metadata = StorageMetadata()
                metadata.contentType = "image/jpeg"
                storageRef.child(imagePath).putData(imageData!, metadata: metadata) { (metadata, error) in
                    if let error = error {
                        print("Error uploading photo: \(error)")
                        return
                    }
                    self.setImageURL(self.storageRef.child((metadata?.path)!).description, forPhotoMessageWithKey: key)
                }
            }        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion:nil)
    }
    
    func checkPermission() {
        let photoAuthorizationStatus = PHPhotoLibrary.authorizationStatus()
        switch photoAuthorizationStatus {
        case .authorized:
            print("Access is granted by user")
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization({
                (newStatus) in
                print("status is \(newStatus)")
                if newStatus ==  PHAuthorizationStatus.authorized {
                    print("success")
                }
            })
            print("It is not determined until now")
        case .restricted:
            print("User do not have access to photo album.")
        case .denied:
            print("User has denied the permission.")
        }
    }
}



