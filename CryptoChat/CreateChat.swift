//
//  CreateChat.swift
//  CryptoChat
//
//  Created by Andy on 12/2/17.
//  Copyright © 2017 ahutch. All rights reserved.
//

import UIKit
import Firebase
import Security
import CryptoSwift

class CreateChat: UIViewController {
    
    struct keyData {
        var b64Identity = ""
        var b64Prekey = ""
        var b64Signature = ""
    }
    
    var chatId = ""
    var originatingUsername = ""
    var friendName = ""
    var friendUID = ""
    var error: Unmanaged<CFError>?
    let dict: [String: Any] = [:]
    
    @IBOutlet weak var friendTextField: UITextField!
    
    let usernamesRef = Database.database().reference(withPath:"usernames")
    let userRef = Database.database().reference(withPath:"users")
    let chatsRef = Database.database().reference(withPath:"chats")
    let keysRef = Database.database().reference(withPath:"keys")
    let user = Auth.auth().currentUser!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    @IBAction func createChat(_ sender: Any) {
        if friendTextField.text! != ""{
            friendName = friendTextField.text!
            chatId = user.uid + friendTextField.text!
            usernamesRef.observeSingleEvent(of: .value, with: { snapshot in
                let snapvalue = snapshot.value as! [String:String]
                //found friend uid
                if let friendUid = snapvalue[self.friendTextField.text!]{
                    self.friendUID = friendUid
                    self.keysRef.child(friendUid).observeSingleEvent(of: .value, with: { keysSnapshot in
                        let keysSnapvalue = keysSnapshot.value as! [String: Any]
                        var identityB64 = ""
                        var preB64 = ""
                        var signatureB64 = ""
                        for (type, response) in keysSnapvalue{
                            if type == "identity"{
                                identityB64 = (response as! [String:String])["key"]!
                            }
                            else if type == "prekey"{
                                preB64 = (response as! [String:String])["key"]!
                                signatureB64 = (response as! [String:String])["signature"]!
                            }
                        }
                        let keysData = keyData(b64Identity: identityB64, b64Prekey: preB64, b64Signature: signatureB64)
                        do {
                            try self.initiateSession(keysData)
                        } catch {
                            print("Error initializing chat")
                        }
                    })
                }
            })
            
        }
        
        self.dismiss(animated: true, completion: nil)
    }
    
    func initiateSession(_ keysData: keyData) throws{
        var masterSecret = ""
        
        let idTag = user.uid + "identity"
        let prekeyTag = user.uid + "prekey"
        let algorithm: SecKeyAlgorithm = .ecdsaSignatureRFC4754
        
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
            throw "Error retrieving key"
        }
        status = SecItemCopyMatching(getPreQuery as CFDictionary, &prekeyRef)
        guard status == errSecSuccess else {
            throw "Error retrieving key"
        }
        
        let identityPrivate = identityRef as! SecKey
        let prekeyPrivate = prekeyRef as! SecKey
        
        guard let identityData = Data.init(base64Encoded: keysData.b64Identity) else {
            return
        }
        guard let prekeyData = Data.init(base64Encoded: keysData.b64Prekey) else {
            return
        }
        guard let signatureData = Data.init(base64Encoded: keysData.b64Signature) else {
            return
        }
        
        let keyDict:[String:Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 256,
            kSecReturnPersistentRef as String: true
        ]
        
        guard let friendIdentityPublic = SecKeyCreateWithData(identityData as CFData, keyDict as CFDictionary, nil) else {
            return
        }
        guard SecKeyIsAlgorithmSupported(friendIdentityPublic, .verify, algorithm) else {
            throw "error"
        }
        guard SecKeyVerifySignature(friendIdentityPublic,
                                    algorithm,
                                    prekeyData as CFData,
                                    signatureData as CFData,
                                    &error) else {
                                        throw error!.takeRetainedValue() as Error
        }
        
        print("prekey signature verified")
        
        guard let friendPrekeyPublic = SecKeyCreateWithData(prekeyData as CFData, keyDict as CFDictionary, nil) else {
            return
        }
        
        instantiateChat(initIdentity: identityPrivate, recipSigned: friendPrekeyPublic, recipIdentity: friendIdentityPublic)
    }
    
    //Chat session has been created successfully by initiator
    func instantiateChat(initIdentity:SecKey, recipSigned: SecKey, recipIdentity: SecKey) {
        let attributes: [String: Any] = [
            kSecAttrKeySizeInBits as String:      256,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true
            ]
        ]
        
        guard let ephemeralPrivate = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
             print(error!.takeRetainedValue())
            return
        }
        var ephemeralPublic = SecKeyCopyPublicKey(ephemeralPrivate)!
        var initPublic = SecKeyCopyPublicKey(initIdentity)!
        
        guard let ecdh1 = SecKeyCopyKeyExchangeResult(initIdentity, SecKeyAlgorithm.ecdhKeyExchangeStandard, recipSigned, dict as CFDictionary, &error) else {
            return
        }
        guard let ecdh2 = SecKeyCopyKeyExchangeResult(ephemeralPrivate, SecKeyAlgorithm.ecdhKeyExchangeStandard, recipIdentity, dict as CFDictionary, &error) else {
            return
        }
        guard let ecdh3 = SecKeyCopyKeyExchangeResult(ephemeralPrivate, SecKeyAlgorithm.ecdhKeyExchangeStandard, recipSigned, dict as CFDictionary, &error) else {
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
        
        guard let ephemeralData = SecKeyCopyExternalRepresentation(ephemeralPublic, &error) else {
            print("Unable to get data from public key")
            return
        }
        guard let identityData = SecKeyCopyExternalRepresentation(initPublic, &error) else {
            print("Unable to get data from public key")
            return
        }
        let b64ephemeral = (ephemeralData as Data).base64EncodedString()
        let b64identity = (identityData as Data).base64EncodedString()
        
        userRef.child(user.uid).child("chats").updateChildValues([chatId:friendName])
        //Adds chat to friend account
        usernamesRef.observeSingleEvent(of: .value, with: { snapshot in
            let snapvalue = snapshot.value as! [String: String]
            for (username, uid) in snapvalue{
                if uid == self.user.uid{
                    self.userRef.child(self.friendUID).child("invites").updateChildValues([self.chatId:username])
                }
            }
        })
        //creates a chat at chatRef
        chatsRef.child(chatId).child("creation").setValue(Int(Date.timeIntervalSinceReferenceDate * 1000))
        var keyUpload:[String:String] = [:]
        keyUpload["ephemeral"] = b64ephemeral
        keyUpload["identity"] = b64identity
        chatsRef.child(chatId).child("initKeys").updateChildValues(keyUpload)
        
    }
    
}
