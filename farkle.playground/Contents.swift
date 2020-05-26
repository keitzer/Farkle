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

struct Hand {
    private let count: Int
    private(set) var dice = [Die]()

    init(count: Int = 6) {
        self.count = count
    }

    func diceDescription() -> String {
        self.dice.map { "\($0.face.rawValue)" }.joined(separator: ", ")
    }

    mutating func roll() {
        if self.dice.count == 0 {
            self.addFullDiceCount()
        }

        self.dice.forEach { $0.roll() }
//        self.sort()
    }

    mutating func removeDice(for score: Score) {
        switch score {
        case .oneOne:
            if let index = dice.firstIndex(where: { $0.face == .one }) {
                self.dice.remove(at: index)
            }
        case .oneFive:
            if let index = dice.firstIndex(where: { $0.face == .five }) {
                self.dice.remove(at: index)
            }
        case let .threeOfAKind(face), let .fourOfAKind(face), let .fiveOfAKind(face):
            self.dice = self.dice.filter { $0.face != face }
        case .sixOfAKind, .oneToSixStraight, .twoTriplets, .threePairs, .fourOfAKindPlusPair:
            self.dice = []
        default: break
        }
    }

    mutating func reset() {
        self.dice.removeAll()
        self.addFullDiceCount()
    }

    private mutating func addFullDiceCount() {
        for _ in 0..<self.count {
            self.dice.append(Die())
        }
    }

    private mutating func sort() {
        self.dice.sort { lhs, rhs in lhs.face.rawValue < rhs.face.rawValue }
    }
}

final class Player: Hashable {
    static func == (lhs: Player, rhs: Player) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    private let id = UUID().uuidString

    /// A point threshold is the "level" at which a player will consider ending their turn,
    /// once their running total for that turn breaches the threshold.
    ///
    /// Example 1: If a player has a `pointThreshold` of 1,000, and their running total is 900,
    /// they will continue to roll every possible dice, regardless of whether or not the dice threshold has been breached.
    ///
    /// Example 2: If a player has a `pointThreshold` of 0, they will end their turn as soon as their `diceThreshold` is breached.
    let pointThreshold: Int

    /// A dice threshold is the "level" at which a player will roll at
    ///
    /// Example 1: If a player has a hand with 4 dice ready to be rolled,
    /// and their dice threshold is 4, they will roll again.
    /// However if that same player has a threshold of 5, they _will not_ roll,
    /// as the number of dice requited to roll is 5, and there are only 4 to be rolled.
    ///
    /// Example 2: `diceThreshold`: 6, `hand.dice.count`: 6... Status: `roll`
    ///
    /// Example 3: `diceThreshold`: 6, `hand.dice.count`: 5... Status: `no roll`
    ///
    /// Example 4: `diceThreshold`: 1, `hand.dice.count`: 1... Status: `roll`
    ///
    /// Example 5: `diceThreshold`: 1, `hand.dice.count`: 4... Status: `roll`
    let diceThreshold: Int

    /// A greedy player is one who will _ALWAYS_ attempt to roll again if their dice threshold has not been breached by the optimal score for a given roll.
    /// A non-greedy player is one who will _ALWAYS_ attempt to end their turn early if it appears taking more dice will breach their dice threshold.
    ///
    /// Example 1: With running total >= 1000, `pointThreshold` == 1,000, and `diceThreshold` of 4... If a given roll of [1, 1, 2, 3, 4] is presented,
    /// A greedy player will take `[1]` and re-roll the remaining 4 dice for a chance at more points (but also a chance at Farkling out)
    /// A non-greedy player will take `[1, 1]` and exit the turn, knowing their dice threshold was breached (but also guaranteeing points)
    let greedy: Bool

    private(set) var score: Int

    /// Initializes a Player object with given thresholds and properties
    ///
    /// - parameter pointThreshold: The running-total at which a player will stop their turn to collect points for a given turn
    /// - parameter diceThreshold: The minimum required dice to roll on a given turn once the point threshold has been breached. Any value less than 1 defaults to 1.
    /// - parameter greedy: How a player decides to handle "post-pointThreshold, but on-the-edge-diceThreshold" scenarios (See `greedy` description). Defaults to false
    init(pointThreshold: Int, diceThreshold: Int, greedy: Bool = false) {
        self.pointThreshold = pointThreshold
        self.diceThreshold = diceThreshold > 0 ? diceThreshold : 1 // 0 makes no sense.
        self.greedy = greedy
        self.score = 0
    }

    var description: String {
        String(id.suffix(5))
    }

    /// Rolls the dice until thresholds are breached.
    func takeTurn() {
        var hand = Hand()
        var scoreThisTurn = 0

        // prevents accidental "dice threshold of 7+ when only 6 dice are in a standard Hand" infinite loops (if that's even possible? lol)
        if hand.dice.count < diceThreshold {
            return
        }

        while true {
            hand.roll()

            print("\n-- ROLL \(hand.dice.count) -------")
            print(hand.diceDescription())

            let bestPointsForRoll = Score.calculateBest(forHand: hand)
            let mostPointsForRoll = Score.calculateTotal(forHand: hand)

            if bestPointsForRoll.isFarkle {
                print("farkle")
                return
            }

            // if all dice can get used, then use all the dice boi
            if mostPointsForRoll.diceRemaining == 0 {
                scoreThisTurn += mostPointsForRoll.points
                hand.reset()
            }
            else if (scoreThisTurn + bestPointsForRoll.value >= self.pointThreshold) ||
                (!greedy && (scoreThisTurn + mostPointsForRoll.points >= self.pointThreshold)) {
                print("point breached: \(scoreThisTurn) +")
                if (hand.dice.count - bestPointsForRoll.amountOfDice) <= diceThreshold {
                    print("dice breached")
                    print(mostPointsForRoll)
                    scoreThisTurn += mostPointsForRoll.points

                    if hand.dice.count - bestPointsForRoll.amountOfDice == 0 && diceThreshold == 0 {
                        self.score = scoreThisTurn // voluntarily ending turn
                        return
                    }
                } else {
                    print("ANOTHER")
                    print(bestPointsForRoll.value)
                    scoreThisTurn += bestPointsForRoll.value // can roll another round since dice threshold not reached
                    hand.removeDice(for: bestPointsForRoll)
                }
            } else {
                print("neither: \(scoreThisTurn) +")
                print(bestPointsForRoll.value)
                scoreThisTurn += bestPointsForRoll.value // can roll another around since point threshold not reached
                hand.removeDice(for: bestPointsForRoll)
            }
        }
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

    var amountOfDice: Int {
        switch self {
        case .oneOne: return 1
        case .oneFive: return 1
        case .threeOfAKind: return 3
        case .fourOfAKind: return 4
        case .fourOfAKindPlusPair: return 6
        case .fiveOfAKind: return 5
        case .sixOfAKind: return 6
        case .oneToSixStraight: return 6
        case .threePairs: return 6
        case .twoTriplets: return 6
        case .farkle: return 0
        }
    }

    var isFarkle: Bool {
        switch self {
        case .farkle: return true
        default: return false
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
        } else if let threeMatchExcludingOneThroughThree = counts.matching(count: 3, excluding: [.one, .two, .three]) {
            return .threeOfAKind(threeMatchExcludingOneThroughThree)
        } else if counts.ones >= 1 {
            return .oneOne
        } else if counts.fives >= 1 {
            return .oneFive
        } else if let threesMatchUsingOneThroughThree = counts.matching(count: 3, excluding: [.four, .five, .six]) {
            return .threeOfAKind(threesMatchUsingOneThroughThree)
        }

        return .farkle
    }

    /// This function calculates the total points for a given hand, including all dice that are point-worthy.
    /// The intention of this function is to be used at the end of a "turn", when a player no longer wishes to roll again.
    /// Using this method, they can maximize their points and gain marginally extra points per turn as opposed to purely using `calculateBest(forHand:)`.
    ///
    /// Example 1: If you roll [1, 1, 4, 4, 4, 6], the total score would be 100 + 100 + 400, or `600` using 5 dice.
    /// Whereas `calculateBest(forHand:)` would return only `400`, using 3 dice.
    ///
    /// - parameter hand: The hand to calculate the score for.
    ///
    /// - returns: The total score for the hand.
    static func calculateTotal(forHand hand: Hand) -> (points: Int, diceRemaining: Int) {
        var tempHand = hand
        var score = calculateBest(forHand: tempHand)
        var totalScore = score.value

        while !score.isFarkle {
            tempHand.removeDice(for: score)
            score = calculateBest(forHand: tempHand)
            totalScore += score.value
        }

        return (points: totalScore, diceRemaining: tempHand.dice.count)
    }
}

final class Game {
    private(set) var players: [Player]

    private(set) var possibleWinner: Player?

    let minimumWinScore: Int

    init?(thresholds: [(point: Int, dice: Int, greedy: Bool)], minimumWinScore: Int = 10000) {
        guard thresholds.count >= 1 else {
            return nil
        }

        self.minimumWinScore = minimumWinScore
        self.players = thresholds.map(Player.init)
    }

    func playRound() {
        for _ in 0 ..< players.count {
            let player = players.remove(at: 0)
            print("\n\nPlayer \(player.description) taking turn: \(player.score)\n")
            player.takeTurn()

            if let currentWinner = possibleWinner, player.score > currentWinner.score {
                possibleWinner = player
            } else if player.score >= minimumWinScore {
                possibleWinner = player
                return // commence final round
            }

            players.append(player)
        }
    }
}

let session = Game(thresholds: [(point: 300, dice: 3, greedy: false)])!

while session.possibleWinner == nil {
    session.playRound()
}

// one final round for everyone else, now that the possible winner is no longer in the "list" of rollers
session.playRound()

if let winner = session.possibleWinner {
    print(winner)
} else {
    print("no winner")
}


/// Using `calculateBest(forHand:)`
// var hand = Hand()
// for _ in 0..<1000 {
//     hand.roll()
//     print(hand.diceDescription())
//     print(Score.calculateBest(forHand: hand))
// }
// Average for 6 dice rolling, over 10k rolls: 299 - 330
// Average for 5 dice rolling, over 10k rolls: 156
// Average for 4 dice rolling, over 10k rolls: 98
// Average for 3 dice rolling, over 10k rolls: 66
// Average for 2 dice rolling, over 10k rolls: 43
// Average for 1 die  rolling, over 10k rolls: 25
