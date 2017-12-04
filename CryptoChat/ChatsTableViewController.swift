//
//  ChatsTableViewController.swift
//  CryptoChat
//
//  Created by Andy on 12/2/17.
//  Copyright © 2017 ahutch. All rights reserved.
//

import UIKit
import Firebase
import CryptoSwift

class ChatsTableViewController: UITableViewController {

    var error: Unmanaged<CFError>?
    let dict: [String: Any] = [:]
    let user = Auth.auth().currentUser!
    let userRef = Database.database().reference(withPath: "users").child((Auth.auth().currentUser?.uid)!).child("username")
    let chatsRef = Database.database().reference(withPath: "users").child((Auth.auth().currentUser?.uid)!).child("chats")
    let invitesRef = Database.database().reference(withPath: "users").child((Auth.auth().currentUser?.uid)!).child("invites")
    let chatRef = Database.database().reference(withPath: "chats")
    var chats: [Chat] = []
    @IBAction func LogoutButtonClicked(_ sender: Any) {
        do {
            //tries signing the user out, and dismisses the current view
            try Auth.auth().signOut()
            dismiss(animated: true, completion: nil)
        }
            //catches any errors in signing out
        catch let error as NSError{
            print(error.localizedDescription)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        chatsRef.observe(.value, with: { snapshot in
            if snapshot.exists(){
                self.chats = []
                let snapvalue = snapshot.value as! [String:String]
                for (chatId, friend) in snapvalue{
                    let chat = Chat(chatId:chatId, friend:friend)
                    self.chats.append(chat)
                }
                self.tableView.reloadData()
            }
        })
        invitesRef.observe(.value, with: { snapshot in
            if snapshot.exists(){
                let snapvalue = snapshot.value as! [String:String]
                for (chatId, sender) in snapvalue {
                    let alert = UIAlertController(title:"Chat Invite",
                                                  message:"Chat with: \(sender)?",
                        preferredStyle:.alert)
                    let saveAction = UIAlertAction(title:"Yes", style: .default)
                    { _ in
                        self.chatsRef.updateChildValues([chatId:sender])
                        self.invitesRef.child(chatId).removeValue()
                        self.initiateChat(chatId, sender)
                    }
                    
                    let cancelAction = UIAlertAction(title:"No", style:.default)
                    { _ in
                        self.invitesRef.child(chatId).removeValue()
                    }
                    alert.addAction(saveAction)
                    alert.addAction(cancelAction)
                    self.present(alert, animated:true, completion:nil)
                }
            }
        })
        
    }


    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return chats.count
    }

    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "chatCell", for: indexPath)
        cell.textLabel?.text = chats[indexPath.row].friend!
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.performSegue(withIdentifier: "toChat", sender: chats[indexPath.row])
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "toChat" {
            let chatVC = segue.destination as! ChatVC
            userRef.observeSingleEvent(of: .value, with: { snapshot in
                let snapValue = snapshot.key
                chatVC.username = snapValue
            })
            chatVC.username = "andy"
            chatVC.chatId = (sender as! Chat).chatId!
        }
    }
}

extension ChatsTableViewController {
    
    func initiateChat(_ chatId: String, _ sender: String){
        
        chatRef.child(chatId).child("initKeys").observeSingleEvent(of: .value, with: { snapshot in
            let snapvalue = snapshot.value as! [String: String]
            var b64ephemeral = ""
            var b64identity = ""
            for (type, key) in snapvalue {
                if type == "ephemeral"{
                    b64ephemeral = key
                } else if type == "identity" {
                    b64identity = key
                }
            }
            self.instantiateChat(chatId: chatId, senderEphemeral: b64ephemeral, senderIdentity: b64identity)
        })
    }
    
    
    func instantiateChat(chatId: String, senderEphemeral: String, senderIdentity: String){
        let idTag = user.uid + "identity"
        let prekeyTag = user.uid + "prekey"
        let algorithm: SecKeyAlgorithm = .ecdsaSignatureRFC4754
        
        let keyDict:[String:Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 256,
            kSecReturnPersistentRef as String: true
        ]
        
        let getIdentityQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: idTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]
        let getPreQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: prekeyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]
        
        var identityRef: CFTypeRef?
        var prekeyRef: CFTypeRef?
        
        var status = SecItemCopyMatching(getIdentityQuery as CFDictionary, &identityRef)
        guard status == errSecSuccess else {
            print("Error retrieving key")
            return
        }
        status = SecItemCopyMatching(getPreQuery as CFDictionary, &prekeyRef)
        guard status == errSecSuccess else {
            print("Error retrieving key")
            return
        }
        
        let identityPrivate = identityRef as! SecKey
        let prekeyPrivate = prekeyRef as! SecKey
        
        guard let ephemeralPublicData = Data.init(base64Encoded: senderEphemeral) else {
            return
        }
        guard let identityPublicData = Data.init(base64Encoded: senderIdentity) else {
            return
        }
        guard let ephemeralPublic = SecKeyCreateWithData(ephemeralPublicData as CFData, keyDict as CFDictionary, nil) else {
            return
        }
        guard let identityPublic = SecKeyCreateWithData(identityPublicData as CFData, keyDict as CFDictionary, nil) else {
            return
        }
        
        guard let ecdh1 = SecKeyCopyKeyExchangeResult(prekeyPrivate, SecKeyAlgorithm.ecdhKeyExchangeStandard, identityPublic, dict as CFDictionary, &error) else {
            return
        }
        guard let ecdh2 = SecKeyCopyKeyExchangeResult(identityPrivate, SecKeyAlgorithm.ecdhKeyExchangeStandard, ephemeralPublic, dict as CFDictionary, &error) else {
            return
        }
        guard let ecdh3 = SecKeyCopyKeyExchangeResult(prekeyPrivate, SecKeyAlgorithm.ecdhKeyExchangeStandard, ephemeralPublic, dict as CFDictionary, &error) else {
            return
        }
        var messageData = NSMutableData()
        messageData.append(ecdh1 as Data)
        messageData.append(ecdh2 as Data)
        messageData.append(ecdh3 as Data)
        let masterSecret = messageData as Data
        
        let chainBytes = masterSecret.bytes
        var chain: [UInt8] = []
        do{
            try chain = HKDF(password: chainBytes, keyLength: 80, variant: .sha256).calculate()
        } catch  {
            print("Couldnt derive key")
        }
        let userDefaults = UserDefaults.standard
        userDefaults.set(chain, forKey: chatId + "chain")
        
        
    }
}
