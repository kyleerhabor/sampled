//
//  SampledTests.swift
//  SampledTests
//
//  Created by Kyle Erhabor on 10/1/25.
//

@testable
import Sampled
import Testing
import PropertyBased

struct SampledTests {
  @Test
  func incrementedIncrements() async {
    await propertyCheck(input: Gen.int()) { number in
      #expect(number.incremented() == number + 1)
    }
  }

  @Test
  func incrementIncrements() async {
    await propertyCheck(input: Gen.int()) { number in
      var n = number
      n.increment()

      #expect(n == number + 1)
    }
  }

  @Test
  func filter() async {
    let range = 0...10

    await propertyCheck(
      input:
        Gen.int(in: range).array(of: range),
        Gen.int(in: range).set(ofAtMost: range),
    ) { numbers, set in
      #expect(numbers.filter(in: set) { $0 }.allSatisfy { set.contains($0) })
    }
  }

  @Test
  func sum() async {
    let count = 10

    await propertyCheck(input: Gen.int(in: Int.min / count ... Int.max / count).array(of: 0...count)) { numbers in
      #expect(numbers.sum() == numbers.reduce(0, +))
    }
  }
}
