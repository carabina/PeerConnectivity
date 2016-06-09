//
//  PeerConnectionViewModel2.swift
//  GameController
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import UIKit
//import Foundation
//import MultipeerConnectivity

public typealias ServiceType = String

public enum PeerConnectionType : Equatable, Hashable {
    case Automatic
    case InviteOnly
    case Custom
    
    public var hashValue : Int {
        switch self {
        case .Automatic:
            return 1
        case .InviteOnly:
            return 2
        case .Custom:
            return 3
        }
    }
}
public func ==(lhs: PeerConnectionType, rhs: PeerConnectionType) -> Bool {
    return lhs.hashValue == rhs.hashValue
}


/*
Functional wrapper for Apple's MultipeerConnectivity framework.
*/
public class PeerConnectionManager {
    
    public let connectionType : PeerConnectionType
    private let serviceType : ServiceType
    
    private let observer = MultiObservable<PeerConnectionEvent>(.Ready)
    
    private let sessionObserver = Observable<PeerSessionEvent>(.None)
    private let browserObserver = Observable<PeerBrowserEvent>(.None)
    private let browserViewControllerObserver = Observable<PeerBrowserViewControllerEvent>(.None)
    private let advertiserObserver = Observable<PeerAdvertiserEvent>(.None)
    private let advertiserAssisstantObserver = Observable<PeerAdvertiserAssisstantEvent>(.None)
    
    private let sessionEventProducer : PeerSessionEventProducer
    private let browserEventProducer : PeerBrowserEventProducer
    private let browserViewControllerEventProducer : PeerBrowserViewControllerEventProducer
    private let advertiserEventProducer : PeerAdvertiserEventProducer
    private let advertiserAssisstantEventProducer : PeerAdvertiserAssisstantEventProducer
    
    public let peer : Peer
    private let session : PeerSession
    private let browser : PeerBrowser
    private let browserAssisstant : PeerBrowserAssisstant
    private let advertiser : PeerAdvertiser
    private let advertiserAssisstant : PeerAdvertiserAssisstant
    
    private let listener : PeerConnectionListener
    
    public var connectedPeers : [Peer] {
        return session.connectedPeers
    }
    
    public var displayNames : [String] {
        return connectedPeers.map { $0.displayName }
    }
    
    public var foundPeers: [Peer] = []
    
    
    public init(serviceType: ServiceType, connectionType: PeerConnectionType = .Automatic, peer: Peer = Peer(displayName: UIDevice.currentDevice().name)) {
        self.connectionType = connectionType
        self.serviceType = serviceType
        self.peer = peer
        
        sessionEventProducer = PeerSessionEventProducer(observer: sessionObserver)
        browserEventProducer = PeerBrowserEventProducer(observer: browserObserver)
        browserViewControllerEventProducer = PeerBrowserViewControllerEventProducer(observer: browserViewControllerObserver)
        advertiserEventProducer = PeerAdvertiserEventProducer(observer: advertiserObserver)
        advertiserAssisstantEventProducer = PeerAdvertiserAssisstantEventProducer(observer: advertiserAssisstantObserver)
        
        session = PeerSession(peer: peer, eventProducer: sessionEventProducer)
        browser = PeerBrowser(session: session, serviceType: serviceType, eventProducer: browserEventProducer)
        browserAssisstant = PeerBrowserAssisstant(session: session, serviceType: serviceType, eventProducer: browserViewControllerEventProducer)
        advertiser = PeerAdvertiser(session: session, serviceType: serviceType, eventProducer: advertiserEventProducer)
        advertiserAssisstant = PeerAdvertiserAssisstant(session: session, serviceType: serviceType, eventProducer: advertiserAssisstantEventProducer)
        
        listener = PeerConnectionListener(observer: observer)
    }
    
    deinit {
        session.stopSession()
        browser.stopBrowsing()
        advertiser.stopAdvertising()
        advertiserAssisstant.stopAdvertisingAssisstant()
        browserAssisstant.stopBrowsingAssistant()
        foundPeers = []
        
        sessionObserver.observers = []
        browserObserver.observers = []
        advertiserObserver.observers = []
        advertiserAssisstantObserver.observers = []
        browserViewControllerObserver.observers = []
        stopListening()
    }
}

extension PeerConnectionManager {
    // MARK: Start/Stop
    
    public func start(completion: (Void->Void)? = nil) {
        
        browserObserver.addObserver { [weak self] event in
            switch event {
            case .FoundPeer(let peer):
                self?.observer.value = .FoundPeer(peer: peer)
            case .LostPeer(let peer):
                self?.observer.value = .LostPeer(peer: peer)
            default: break
            }
        }
        
        advertiserObserver.addObserver { [weak self] event in
            switch event {
            case.DidReceiveInvitationFromPeer(peer: let peer, withContext: let context, invitationHandler: let invitationHandler):
                self?.observer.value = .ReceivedInvitation(peer: peer, withContext: context, invitationHandler: invitationHandler)
            default: break
            }
        }
        
        sessionObserver.addObserver { [weak self] event in
            switch event {
            case .DevicesChanged(peer: let peer):
                guard let connectedPeers = self?.connectedPeers else { return }
                self?.observer.value = .DevicesChanged(peer: peer, connectedPeers: connectedPeers)
            case .DidReceiveData(peer: let peer, data: let data):
                self?.observer.value = .ReceivedData(peer: peer, data: data)
            case .DidReceiveCertificate(peer: let peer, certificate: let certificate, handler: let handler):
                self?.observer.value = .ReceivedCertificate(peer: peer, certificate: certificate, handler: handler)
            case .DidReceiveStream(peer: let peer, stream: let stream, name: let name):
                self?.observer.value = .ReceivedStream(peer: peer, stream: stream, name: name)
            case .StartedReceivingResource(peer: let peer, name: let name, progress: let progress):
                self?.observer.value = .StartedReceivingResource(peer: peer, name: name, progress: progress)
            case .FinishedReceivingResource(peer: let peer, name: let name, url: let url, error: let error):
                self?.observer.value = .FinishedReceivingResource(peer: peer, name: name, url: url, error: error)
            default: break
            }
        }
        
        browserObserver.addObserver { [weak self] event in
            switch event {
            case .FoundPeer(let peer):
                self?.foundPeers.append(peer)
            case .LostPeer(let peer):
                guard let index = self?.foundPeers.indexOf(peer) else { return }
                self?.foundPeers.removeAtIndex(index)
            default: break
            }
            print(self?.foundPeers)
        }
        
        sessionObserver.addObserver { [weak self] event in
            
            guard let peerCount = self?.connectedPeers.count else { return }
            
            switch event {
            case .DevicesChanged(peer: let peer) where peerCount <= 0 :
                switch peer {
                case .NotConnected(_):
                    print("Lost Connection")
                    self?.refresh()
                default: break
                }
            default: break
            }
        }
        
        listener.listenOn(certificateReceived: { (peer, certificate, handler) -> Void in
            print("PeerConnectionManager: listenOn: certificateReceived")
            handler(true)
            }, withKey: "CertificateRecieved")
        
        switch connectionType {
        case .Automatic:
            browserObserver.addObserver { [unowned self] event in
                switch event {
                case .FoundPeer(let peer):
                    print("Invite Peer to session")
                    self.browser.invitePeer(peer)
                default: break
                }
            }
            advertiserObserver.addObserver { [unowned self] event in
                switch event {
                case .DidReceiveInvitationFromPeer(peer: _, withContext: _, invitationHandler: let handler):
                    print("Responding to invitation")
                    handler(true, self.session)
                    self.advertiser.stopAdvertising()
                default: break
                }
            }
        default: break
        }
        
        session.startSession()
        browser.startBrowsing()
        advertiser.startAdvertising()
        
        switch connectionType {
        case .Automatic: break
        case .InviteOnly:
            browserAssisstant.startBrowsingAssisstant()
            advertiserAssisstant.startAdvertisingAssisstant()
        case .Custom: break
        }
        
        completion?()
    }
    
    public func browserViewController() -> UIViewController? {
        switch connectionType {
        case .InviteOnly: return browserAssisstant.peerBrowserViewController()
        default: return nil
        }
    }
    
    public func invitePeer(peer: Peer, withContext context: NSData? = nil, timeout: NSTimeInterval = 30) {
        browser.invitePeer(peer, withContext: context, timeout: timeout)
    }
    
    public func sendData(data: NSData, toPeers peers: [Peer] = []) {
        session.sendData(data, toPeers: peers)
    }
    
    public func sendEvent(eventInfo: [String:AnyObject], toPeers peers: [Peer] = []) {
        let eventData = NSKeyedArchiver.archivedDataWithRootObject(eventInfo)
        session.sendData(eventData, toPeers: peers)
    }
    
    // TODO: Sending resources is untested
    public func sendResourceAtURL(resourceURL: NSURL,
                         withName name: String,
                           toPeer peer: Peer? = nil,
      withCompletionHandler completion: ((NSError?) -> Void)? ) -> [NSProgress?] {
        
        var progress : [NSProgress?] = []
            
        guard let peer = peer
            else {
                for peer in connectedPeers {
                    progress.append(session.sendResourceAtURL(resourceURL, withName: name,
                                                                             toPeer: peer,
                                                              withCompletionHandler: completion))
                }
                return progress
            }
        progress.append(session.sendResourceAtURL(resourceURL, withName: name,
                                                                 toPeer: peer,
                                                  withCompletionHandler: completion))
        return progress
    }
    
    public func refresh(completion: (Void->Void)? = nil) {
        stop()
        start(completion)
    }
    
    public func stop() {
        session.stopSession()
        browser.stopBrowsing()
        advertiser.stopAdvertising()
        advertiserAssisstant.stopAdvertisingAssisstant()
        browserAssisstant.stopBrowsingAssistant()
        foundPeers = []
        
        sessionObserver.observers = []
        browserObserver.observers = []
        advertiserObserver.observers = []
        advertiserAssisstantObserver.observers = []
        browserViewControllerObserver.observers = []
        
        sessionObserver.value = .None
        browserObserver.value = .None
        advertiserObserver.value = .None
        advertiserAssisstantObserver.value = .None
        browserViewControllerObserver.value = .None
    }
}

extension PeerConnectionManager {
    // MARK: Add listener
    
    public func listenOn(ready ready: ReadyListener = { _ in },
        started: StartListener = { _ in },
        devicesChanged: DevicesChangedListener = { _ in },
        eventReceived: EventListener = { _ in },
        dataReceived: DataListener = { _ in },
        streamReceived: StreamListener = { _ in },
        receivingResourceStarted: StartedReceivingResourceListener = { _ in },
        receivingResourceFinished: FinishedReceivingResourceListener = { _ in },
        certificateReceived: CertificateReceivedListener = { _ in },
        ended: SessionEndedListener = { _ in },
        error: ErrorListener = { _ in },
        foundPeer: FoundPeerListener = { _ in },
        lostPeer: LostPeerListener = { _ in },
        receivedInvitation: ReceivedInvitationListener = { _ in },
        withKey key: String) -> PeerConnectionManager {
        
        let invitationReceiver = {
            [weak self]
            (peer: Peer, withContext: NSData?, invitationHandler: (Bool, PeerSession) -> Void) in
            
            guard let session = self?.session else { return }
            receivedInvitation(peer: peer, withContext: withContext, invitationHandler: {
                joinResponse in
                if joinResponse { print("PeerConnectionManager: Join peer session") }
                invitationHandler(joinResponse, session)
            })
        }
        
            listener.listenOn(
                ready: ready,
                started: started,
                devicesChanged: devicesChanged,
                eventReceived: eventReceived,
                dataReceived: dataReceived,
                streamReceived: streamReceived,
                receivingResourceStarted: receivingResourceStarted,
                receivingResourceFinished: receivingResourceFinished,
                certificateReceived: certificateReceived,
                ended: ended,
                error: error,
                foundPeer: foundPeer,
                lostPeer: lostPeer,
                receivedInvitation: invitationReceiver,
                withKey: key)
        
        return self
    }
    
    public func removeListenerForKey(key: String) {
        listener.removeListenerForKey(key)
    }
    
    private func stopListening() {
        listener.stopListening()
    }
}