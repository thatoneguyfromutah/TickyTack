//
//  Tack.swift
//  TickyTack
//
//  Created by Chase Angelo Giles on 9/18/25.
//

import Foundation

class Tack: NSObject {
    
    // MARK: - Properties
    
    var videoURL: URL?
    
    // MARK: - Initialization
    
    init(videoURL: URL? = nil) {
        self.videoURL = videoURL
    }
}
