import UIKit

enum DieFace: Int {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6
}

final class Die {
    private(set) var face: DieFace = .one

    func roll() {
        self.face = DieFace(rawValue: Int((arc4random() % 6) + 1)) ?? .one
    }
}

final class Hand {
    private(set) var dice: [Die]

    init() {
        self.dice = [Die(), Die(), Die(), Die(), Die(), Die()]
    }

    func roll() {
        self.dice.forEach { $0.roll() }
        self.dice.sort { lhs, rhs in lhs.face.rawValue < rhs.face.rawValue }
    }

    func printDice() {
        print(self.dice.map { "\($0.face.rawValue)" }.joined(separator: ", "))
    }
}

enum Score {
    case oneOne
    case oneFive
    case threeOfAKind(DieFace)
    case fourOfAKind(DieFace)
    case fourOfAKindPlusPair
    case fiveOfAKind(DieFace)
    case sixOfAKind
    case oneToSixStraight
    case threePairs
    case twoTriplets
    case farkle

    var value: Int {
        switch self {
        case .oneOne: return 100
        case .oneFive: return 50
        case .threeOfAKind(let face): return face == .one ? 300 : face.rawValue * 100
        case .fourOfAKind: return 1000
        case .fourOfAKindPlusPair: return 1500
        case .fiveOfAKind: return 2000
        case .sixOfAKind: return 3000
        case .oneToSixStraight: return 1500
        case .threePairs: return 1500
        case .twoTriplets: return 2500
        case .farkle: return 0
        }
    }

    private struct DiceCounts {
        var ones = 0
        var twos = 0
        var threes = 0
        var fours = 0
        var fives = 0
        var sixes = 0

        init(for hand: Hand) {
            hand.dice.forEach {
                switch $0.face {
                case .one: ones += 1
                case .two: twos += 1
                case .three: threes += 1
                case .four: fours += 1
                case .five: fives += 1
                case .six: sixes += 1
                }
            }
        }

        func matching(count: Int, excluding: [DieFace] = []) -> DieFace? {
            if !excluding.contains(.one) && self.ones == count {
                return .one
            } else if !excluding.contains(.two) && self.twos == count {
                return .two
            } else if !excluding.contains(.three) && self.threes == count {
                return .three
            } else if !excluding.contains(.four) && self.fours == count {
                return .four
            } else if !excluding.contains(.five) && self.fives == count {
                return .five
            } else if !excluding.contains(.six) && self.sixes == count {
                return .six
            }

            return nil
        }
    }

    /// This function is intended to calculate the best score for a given hand.
    /// It assumes less dice used for an equal score is unequivocally better.
    /// Therefore it looks to find the highest possible score using the fewest possible dice.
    ///
    /// Example 1: If you have the option to choose 2 fives or 1 one, this function will return 1 one,
    /// since it uses the less dice to achieve the same score.
    ///
    /// Example 2: If you have the option to choose 3 ones or 4 ones, this function will return the four of a kind.
    /// Even though it's a higher dice count, it is a higher marginal value (1 extra dice for 700 points in this case).
    ///
    /// Example 3: If you have the option to choose 1 five or 2 fives, this function will return 1 five,
    /// since it uses less dice and the marginal gain might be higher on the following roll.
    ///
    /// - parameter hand: The hand to calculate the score for.
    ///
    /// - returns: The highest possible score using the fewest possible dice.
    static func calculateBest(forHand hand: Hand) -> Score {
        let counts = DiceCounts(for: hand)

        let faces = hand.dice.map { $0.face.rawValue }

        if counts.matching(count: 6) != nil {
            return .sixOfAKind
        } else if let firstTriplet = counts.matching(count: 3),
            counts.matching(count: 3, excluding: [firstTriplet]) != nil {
            return .twoTriplets
        } else if let fiveMatch = counts.matching(count: 5) {
            return .fiveOfAKind(fiveMatch)
        } else if faces == [1, 2, 3, 4, 5, 6] {
            return .oneToSixStraight
        } else if let firstPair = counts.matching(count: 2),
            let secondPair = counts.matching(count: 2, excluding: [firstPair]),
            counts.matching(count: 2, excluding: [firstPair, secondPair]) != nil {
            return .threePairs
        } else if let firstFour = counts.matching(count: 4),
            counts.matching(count: 2, excluding: [firstFour]) != nil {
            return .fourOfAKindPlusPair
        } else if let fourMatch = counts.matching(count: 4) {
            return .fourOfAKind(fourMatch)
        } else if let threeMatch = counts.matching(count: 3) {
            return .threeOfAKind(threeMatch)
        } else if counts.ones >= 1 {
            return .oneOne
        } else if counts.fives >= 1 {
            return .oneFive
        }

        return .farkle
    }
}

//struct Game {
//    private(set) var players: [Hand]
//
//    init(numberOfPlayers: Int) {
//        self.players = Array(repeating: Hand(), count: numberOfPlayers)
//    }
//
//    func playRound() {
//        players.forEach {
//            $0.roll()
//            $0.printRoll()
//            Score.calculateBest(forHand: $0)
//        }
//    }
//}

//var game = Game(numberOfPlayers: 1)

var hand = Hand()

for _ in 0..<1000 {
    hand.roll()
    hand.printDice()
    print(Score.calculateBest(forHand: hand))
}
