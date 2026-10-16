//
//  AuthServerConfig.swift
//  RegistrationKit
//
//  Points a DEVELOPMENT build at the real Auth Server (AuthServer/, `docker compose
//  up`) running on your Mac. A real device can't reach "localhost" and mean
//  the Mac — that resolves to the device itself — so this has to be the
//  Mac's local network name (Bonjour, `<LocalHostName>.local`), reachable over
//  the same Wi-Fi network as the device. A name, not the LAN IP: the IP is
//  DHCP-assigned and can change; the name follows the Mac. Check it
//  with `scutil --get LocalHostName`, and change it here if the Mac is
//  renamed. Reaching it needs the Local Network permission on a phone (the
//  apps ask for it). This is local-dev-only
//  plumbing — plain HTTP only works here because of the
//  NSAllowsLocalNetworking exception in each app's Info.plist settings,
//  which is explicitly scoped to local networking, not a general ATS bypass.
//
//  Never the address of a shipped build: the real app refuses to compile in
//  Release while this is the only address it has.
//

import Foundation

public enum AuthServerConfig {
    public static let localDevelopmentURL = URL(string: "http://docs-MacBook-Pro-2.local:8080")!
}
