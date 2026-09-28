//
//  AuthServerConfig.swift
//  AppAttestTestApp
//
//  Points the harness at the real Auth Server (AuthServer/, `docker compose
//  up`) running on your Mac. A real device can't reach "localhost" and mean
//  the Mac — that resolves to the device itself — so this has to be the
//  Mac's LAN IP, reachable over the same Wi-Fi network as the device.
//
//  DHCP-assigned, so it WILL change if your Mac reconnects to Wi-Fi or your
//  router reassigns leases. Update it (`ipconfig getifaddr en0` in Terminal)
//  when requests start failing for no other reason. This is local-dev-only
//  plumbing — plain HTTP only works here because of the
//  NSAllowsLocalNetworking exception in the Xcode project's Info.plist
//  settings, which is explicitly scoped to local networking, not a general
//  ATS bypass.
//

import Foundation

enum AuthServerConfig {
    static let baseURL = URL(string: "http://192.168.0.84:8080")!
}
