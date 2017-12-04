//
//  RegistrationViewController.swift
//  InterfaceTesting
//
//  Created by Andy on 9/18/17.
//  Copyright © 2017 ahutch. All rights reserved.
//

import UIKit
import Firebase
import Security
import CryptoSwift

class RegistrationViewController: UIViewController {
    
    var error: Unmanaged<CFError>?
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var usernameTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    
    @IBOutlet weak var signupButton: UIButton!
    @IBAction func signupButtonPressed(_ sender: Any) {
        var newUser: [String: Any] = [:]
        Auth.auth().createUser(withEmail: emailTextField.text!, password: passwordTextField.text!, completion: { user, error in
            if user != nil {
                let userRef = Database.database().reference(withPath:"users").child((user?.uid)!)
                newUser["email"] = self.emailTextField.text!
                newUser["username"] = self.usernameTextField.text!
                userRef.setValue(newUser)
                self.addUsername(uid:(user?.uid)!, username: self.usernameTextField.text!)
                do{
                    try self.addKeys(user!.uid)
                } catch {
                    print("Error creating keys")
                }
                self.dismiss(animated: false, completion: nil)
            }
            else {
                print(error.debugDescription)
            }
        })
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let picRightBorder = CALayer()
        let width = CGFloat(1.0)
        picRightBorder.borderColor = UIColor.white.cgColor
        picRightBorder.frame = CGRect(x: 79, y: 0, width:  1, height: 80)
        picRightBorder.borderWidth = width
        
        bottomBorder(formView:usernameTextField)
        bottomBorder(formView:emailTextField)
        bottomBorder(formView:passwordTextField)
    }
    
    func bottomBorder(formView: UIView){
        let width = CGFloat(1.0)
        let bottomBorder = CALayer()
        bottomBorder.borderColor = UIColor.white.cgColor
        bottomBorder.frame = CGRect(x: 0, y: formView.frame.size.height - width, width:  formView.frame.size.width, height: formView.frame.size.height)
        bottomBorder.borderWidth = width
        formView.layer.addSublayer(bottomBorder)
        formView.layer.masksToBounds = true
    }
    
    func query(type:String, tag:String, privateKey:SecKey?) -> [String:Any] {
        var query: [String: Any] = [:]
        query[kSecClass as String] = kSecClassKey
        query[kSecAttrApplicationTag as String] = tag
        if type == "add" {
            query[kSecValueRef as String] = privateKey!
        } else {
            query[kSecAttrKeyType as String] = kSecAttrKeyTypeECSECPrimeRandom
            query[kSecReturnRef as String] = true
        }
        return query
    }
    
    func addKeys(_ uid: String) throws{
        var publicKey: SecKey?
        
        let attributes: [String: Any] = [
            kSecAttrKeySizeInBits as String:      256,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true
            ]
        ]
        
        guard let identityPrivate = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        guard let preKeyPrivate = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        
        let idTag = uid + "identity"
        let prekeyTag = uid + "prekey"
        
        let addIdentityQuery: [String: Any] = [kSecClass as String: kSecClassKey,
                                       kSecAttrApplicationTag as String: idTag,
                                       kSecValueRef as String: identityPrivate]
        let addPreQuery: [String: Any] = [kSecClass as String: kSecClassKey,
                                              kSecAttrApplicationTag as String: prekeyTag,
                                              kSecValueRef as String: preKeyPrivate]
        
        var status = SecItemAdd(addIdentityQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw "Error adding Identity key"
        }
        
        status = SecItemAdd(addPreQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw "Error adding Prekey"
        }
        
        var identityPublic = SecKeyCopyPublicKey(identityPrivate)!
        var prekeyPublic = SecKeyCopyPublicKey(preKeyPrivate)!
        
        let algorithm: SecKeyAlgorithm = .ecdsaSignatureRFC4754
        guard SecKeyIsAlgorithmSupported(identityPrivate, .sign, algorithm) else {
            throw "algorithm not supported"
        }
        
        
        guard let identityData = SecKeyCopyExternalRepresentation(identityPublic, &error) else {
            print("Unable to get data from public key")
            throw "Unable to get data from public key"
        }
        guard let prekeyData = SecKeyCopyExternalRepresentation(prekeyPublic, &error) else {
            print("Unable to get data from public key")
            throw "Unable to get data from public key"
        }
        guard let signature = SecKeyCreateSignature(
            identityPrivate,
            algorithm,
            prekeyData,
            &error) as Data? else {
                print(error!.takeRetainedValue())
                throw error!.takeRetainedValue() as Error
        }
        
        let b64Identity = (identityData as Data).base64EncodedString()
        let b64prekey = (prekeyData as Data).base64EncodedString()
        let b64Signature = signature.base64EncodedString()
        
        //upload b64identity, b64prekey, signature
        let keyRef = Database.database().reference(withPath: "keys").child(uid)
        keyRef.child("identity").updateChildValues(["key":b64Identity])
        keyRef.child("prekey").updateChildValues(["key":b64prekey])
        keyRef.child("prekey").updateChildValues(["signature":b64Signature])
        
        /*
        guard let dataFromServer = Data.init(base64Encoded: b64Key) else {
            return
        }
        
        guard SecKeyIsAlgorithmSupported(identityPublic, .verify, algorithm) else {
            print("cant verify")
            throw "error"
        }
        
        guard SecKeyVerifySignature(identityPublic,
                                    algorithm,
                                    dataFromServer as CFData,
                                    signature as CFData,
                                    &error) else {
                                        throw error!.takeRetainedValue() as Error
        }
        
        print("signature verified")
        
        let keyDict:[String:Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 256,
            kSecReturnPersistentRef as String: true
        ]
    */
        
    }
    
    func addUsername(uid: String, username: String){
        let usernameRef = Database.database().reference(withPath:"usernames")
        usernameRef.updateChildValues([username: uid] )
    }
    
}

extension String: Error {}

/*
 //        let addIdentityQuery = query(type: "add", tag: "identity", privateKey: identityPrivate)
 //        let addPreKeyQuery = query(type: "add", tag: "prekey", privateKey: preKeyPrivate)
 //
 //        let getIdentityQuery = query(type: "pull", tag: "identity", privateKey: nil)
 //        let getPrekeyQuery = query(type: "pull", tag: "prekey", privateKey: nil)
 
 let getIdentityQuery: [String: Any] = [kSecClass as String: kSecClassKey,
 kSecAttrApplicationTag as String: "i4",
 kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
 kSecReturnRef as String: true]
 let getPreQuery: [String: Any] = [kSecClass as String: kSecClassKey,
 kSecAttrApplicationTag as String: "pre4",
 kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
 kSecReturnRef as String: true]
 
 var item: CFTypeRef?
 var item2: CFTypeRef?
 
 status = SecItemCopyMatching(getIdentityQuery as CFDictionary, &item)
 guard status == errSecSuccess else {
 throw "Error retrieving key"
 }
 let iKey = item as! SecKey
 print("IP: \(SecKeyCopyPublicKey(iKey)!)")
 
 status = SecItemCopyMatching(getPreQuery as CFDictionary, &item2)
 guard status == errSecSuccess else {
 throw "Error retrieving key"
 }
 let pKey = item2 as! SecKey
 print("PP: \(SecKeyCopyPublicKey(pKey)!)")
 
 var b64Key = ""
 if let cfdata = SecKeyCopyExternalRepresentation(SecKeyCopyPublicKey(pKey)!, &error) {
 let data:Data = cfdata as Data
 b64Key = data.base64EncodedString()
 }
 
 guard let data2 = Data.init(base64Encoded: b64Key) else {
 return
 }
 
 let keyDict:[String:Any] = [
 kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
 kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
 kSecAttrKeySizeInBits as String: 256,
 kSecReturnPersistentRef as String: true
 ]
 
 guard let pKeyRet = SecKeyCreateWithData(data2 as CFData, keyDict as CFDictionary, nil) else {
 return
 }
 
 print("pp retrieved: \(pKeyRet)")
 
 
 */

