//
//  CustomJSQPhotoMediaItem.swift
//  TravelApp_2
//
//  Created by Andy on 8/21/17.
//  Copyright © 2017 ahutch. All rights reserved.
//

import Foundation
import JSQMessagesViewController

class CustomJSQPhotoMediaItem: JSQPhotoMediaItem {
    override init!(image: UIImage!) {
        super.init(image: image)
    }
    
    override init!(maskAsOutgoing: Bool) {
        super.init(maskAsOutgoing: maskAsOutgoing)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    override func mediaViewDisplaySize() -> CGSize {
        if let image = image {
            let ratio = self.image.size.height / self.image.size.width
            let w = min(UIScreen.main.bounds.width * 0.6, self.image.size.width)
            let h = w * ratio
            return CGSize(width: w, height: h)
        }
        else {
            return super.mediaViewDisplaySize()
        }
        
    }
}

