//
//  PeerBrowser.swift
//  GameController
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

internal struct PeerBrowser {
    
    private let session : PeerSession
    private let browser : MCNearbyServiceBrowser
    private let eventProducer : PeerBrowserEventProducer
    
    internal init(session: PeerSession, serviceType: ServiceType, eventProducer: PeerBrowserEventProducer) {
        self.session = session
        self.eventProducer = eventProducer
        browser = MCNearbyServiceBrowser(peer: session.peer.peerID, serviceType: serviceType)
        browser.delegate = eventProducer
    }
    
    internal func invitePeer(peer: Peer, withContext context: NSData? = nil, timeout: NSTimeInterval = 30) {
        browser.invitePeer(peer.peerID, toSession: session.session, withContext: context, timeout: timeout)
    }
    
    internal func startBrowsing() {
        browser.delegate = eventProducer
        browser.startBrowsingForPeers()
    }
    
    internal func stopBrowsing() {
        browser.stopBrowsingForPeers()
        browser.delegate = nil
    }
    
}