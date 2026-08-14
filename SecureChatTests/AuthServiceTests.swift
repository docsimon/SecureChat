//
//  AuthServiceTests.swift
//  SecureChat
//
//  Created by Simone Barbara on 14/08/2026.
//

import XCTest
@testable import SecureChat

final class AuthServiceTests: XCTestCase {
   
    func test_register() async throws {
        let networkAdapterMock = NetworkAdapterMock()
        let jsonAdapter = JSONAdapterImpl()
        
        let userID = UUID(uuidString: "F709E72C-10AE-41CB-AE02-324BB7EB569E")!
        let phone = "+441234 56789"
        let username = "Simon"
        let token = "my pn token"
       
        let registerDTO = RegistrationDTO(userID: userID, phone: phone, username: username, token: token)
        
        let authService = AuthServiceImpl(networkAdapter: networkAdapterMock, jsonAdapter: jsonAdapter)
        
        try await authService.register(data: registerDTO)
        let request = try XCTUnwrap(networkAdapterMock.mockRequest)
        XCTAssertTrue(request.httpMethod == "POST")
        let body = try XCTUnwrap(request.httpBody)
        let newRegistrationDTO: RegistrationDTO = try jsonAdapter.deserialize(data: body)
        XCTAssertTrue(newRegistrationDTO.phone == "+441234 56789")
        XCTAssertTrue(newRegistrationDTO.username == "Simon")
        XCTAssertTrue(newRegistrationDTO.userID == userID)
        XCTAssertTrue(newRegistrationDTO.token == "my pn token")
    }
}
