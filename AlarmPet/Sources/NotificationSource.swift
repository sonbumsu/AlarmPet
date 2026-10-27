// NotificationSource.swift
// Common shape for everything that can make the pet talk.

import Foundation

protocol NotificationSource: AnyObject {
    var onMessage: ((PetMessage) -> Void)? { get set }
    func start()
    func stop()
}
