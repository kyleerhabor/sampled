//
//  UI+Model.swift
//  Sampled
//
//  Created by Kyle Erhabor on 8/19/25.
//

import CryptoKit
import Foundation

// In Info structs, CodingKeys with a prefixed string value are there to disambiguate it from the returned rows when
// decoding.

func hash(data: some DataProtocol) -> Data {
  Data(SHA256.hash(data: data))
}
