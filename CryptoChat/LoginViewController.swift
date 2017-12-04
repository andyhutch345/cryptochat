//
//  ViewController.swift
//  InterfaceTesting
//
//  Created by Andy on 8/16/17.
//  Copyright © 2017 ahutch. All rights reserved.
//

import UIKit
import Firebase 

class LoginViewController: UIViewController, UITextFieldDelegate {
    
    var activeTextField = UITextField()
    let defaults = UserDefaults.standard
    let sharedDefaults = UserDefaults.init(suiteName: "group.ArticleShareExtensionAG")!
    var profilePicture: UIImage?
    
    @IBOutlet weak var dialogView: DesignableView!
    @IBOutlet weak var emailTextField: DesignableTextField!
    @IBOutlet weak var passwordTextField: DesignableTextField!
    @IBOutlet weak var incorrectLoginLabel: UILabel!
    
    @IBOutlet weak var emailImageView: SpringImageView!
    @IBOutlet weak var passwordImageView: SpringImageView!
    @IBOutlet weak var signInButton: DesignableButton!
    
    
    var validEmail: Bool = false{
        didSet{
            if validPassword == true && validEmail == true{
                validLogin = true
            }
            else{
                validLogin = false
            }
        }
    }
    var validPassword: Bool = false {
        didSet{
            if validPassword == true && validEmail == true{
                validLogin = true
            }
            else{
                validLogin = false
            }
        }
    }
    var validLogin: Bool = false{
        didSet {
            if validLogin == true {
                signInButton.isEnabled = true
                signInButton.alpha = 1.0
            }
            else {
                signInButton.isEnabled = false
                signInButton.alpha = 0.5
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        emailTextField.delegate = self
        passwordTextField.delegate = self
        
        self.emailTextField.addTarget(self, action: #selector(textFieldDidEditingChange(_:)), for: .editingChanged)
        self.passwordTextField.addTarget(self, action: #selector(textFieldDidEditingChange(_:)), for: .editingChanged)
        
        Auth.auth().addStateDidChangeListener() { auth, user  in
            if user != nil {
                self.performSegue(withIdentifier: "toChats", sender: nil)
            }
        }
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        Auth.auth().addStateDidChangeListener() { auth, user  in
            if user != nil {
                self.sharedDefaults.set(true, forKey: "isLoggedIn")
                self.performSegue(withIdentifier: "toChats", sender: nil)
            }
        }
    }
    
    @IBAction func loginButtonDidTouch(_ sender: Any) {
        Auth.auth().signIn(withEmail: emailTextField.text!, password: passwordTextField.text!, completion: { (user, error) in
            if user != nil{
                self.sharedDefaults.set(true, forKey: "isEmailCredential")
                self.sharedDefaults.set(self.emailTextField.text!, forKey: "email")
                print("user successfully signed in")
            }
            else{
                print("User auth failed")
                self.dialogView.animation = "shake"
                self.dialogView.animate()
                self.incorrectLoginLabel.isHidden = false
            }
        })
        
    }
    
    @objc func textFieldDidEditingChange(_ textField: UITextField) {
        activeTextField = textField
        incorrectLoginLabel.isHidden = true
        if textField == emailTextField{
            validEmail = isValidEmail(email: textField.text!)
        }
        else if textField == passwordTextField{
            validPassword = isValidPassword(password: textField.text!)
        }
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        activeTextField = textField
        
        if activeTextField == emailTextField{
            emailImageView.isHighlighted = true
            passwordImageView.isHighlighted = false
        }
        else if activeTextField == passwordTextField{
            emailImageView.isHighlighted = false
            passwordImageView.isHighlighted = true
        }
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        emailImageView.isHighlighted = false
        passwordImageView.isHighlighted = false
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        activeTextField = textField
        if activeTextField == emailTextField, validEmail == true{
            passwordTextField.becomeFirstResponder()
            return true
        }
        else if activeTextField == passwordTextField, validLogin == true{
            textField.resignFirstResponder()
            loginButtonDidTouch(textField)
            return true
        }
        return false
    }
    
    func isValidEmail(email:String?) -> Bool{
        if let email = email{
            let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
            let emailTest = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
            return emailTest.evaluate(with: email)
        }
        else{
            return false
        }
    }
    
    func isValidPassword(password: String?) -> Bool{
        if let password = password{
            if password.length > 5{
                return true
            }
            else{
                return false
            }
        }
        else{
            return false
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        view.endEditing(true)
    }
    
    
}




