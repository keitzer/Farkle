import UIKit

var isLoggingEnabled = true
func debugLog(_ value: String = "") {
    guard isLoggingEnabled else {
        return
    }

    print(value)
}

extension Double {
    func round(to places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

extension Array where Iterator.Element == Double {
    func standardDeviation() -> Double {
        let length = Double(self.count)
        let average = self.reduce(0, {$0 + $1}) / length
        let sumOfSquaredAverageDiff = self.map { pow($0 - average, 2.0)}.reduce(0, {$0 + $1})
        return sqrt(sumOfSquaredAverageDiff / length)
    }
}

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
        self.addFullDiceCount()
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

struct PlayerVariation {
    var point: Int
    var dice: Int
    var greedy: Bool
    var final: Bool
}

final class Player: Hashable {
    private let id = UUID().uuidString

    /// A point threshold is the "level" at which a player will consider ending their turn,
    /// once their running total for that turn breaches the threshold.
    ///
    /// Example 1: If a player has a `pointThreshold` of 1,000, and their running total is 900,
    /// they will continue to roll every possible dice, regardless of whether or not the dice threshold has been breached.
    ///
    /// Example 2: If a player has a `pointThreshold` of 0, they will end their turn as soon as their `diceThreshold` is breached.
    private(set) var pointThreshold: Int

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

    /// If true, acts as if the point threshold is the winner's score minus their current score
    let playsFinalTurnDifferently: Bool

    weak var scoreboard: ScoreManager?

    var score: Int {
        scoreboard?.score(for: self) ?? -1
    }

    var requiredToGetOnTheBoard = 0

    init(variation: PlayerVariation) {
        self.pointThreshold = variation.point
        self.diceThreshold = variation.dice > 0 ? variation.dice : 1 // 0 makes no sense.
        self.greedy = variation.greedy
        self.playsFinalTurnDifferently = variation.final
    }

    var description: String {
        String(id.suffix(5))
    }

    var fullDescription: String {
        description + " has a score of \(self.score) using a pointThreshold of \(self.pointThreshold) and a diceThreshold of \(self.diceThreshold) while being \(self.greedy ? "" : "NOT ")greedy and \(self.playsFinalTurnDifferently ? "" : "NOT ")playing final turns until victory or farkle"
    }

    /// Rolls the dice until thresholds are breached.
    func takeTurn() {
        var hand = Hand()
        var scoreThisTurn = 0

        // prevents accidental "dice threshold of 7+ when only 6 dice are in a standard Hand" infinite loops (if that's even possible? lol)
        if hand.dice.count < diceThreshold {
            debugLog("below dice threshold, \(hand.dice.count) versus dt of \(diceThreshold)")
            return
        }

        var doneRolling = false

        /// eg: pointThreshold is 300, required to get on board 500, current score 0 ... this value becomes 500
        ///
        /// eg: pointThreshold is 600, required to get on board 500, current score 0... this value becomes 600
        ///
        /// eg: pointThreshold is 300, required to get on board 500, current score is 600 ... this value becomes 300
        ///
        /// eg: pointThreshold is temp 2800, up from 300 (eg: end of game), required to get on board 500, current score is 9300... this value becomes 2800
        /// eg: pointThreshold is 300, required to get on board now-later-on becomes 5000 (aka: "moving gate" rule), current score is 4000... this value becomes 1000
        let requiredScoreThisTurnBeforeAllowedToEnd = max(self.pointThreshold, (self.requiredToGetOnTheBoard - self.score))

        while !doneRolling {
            hand.roll()

            debugLog("\n-- 🎲 ROLL \(hand.dice.count) -------")
            debugLog(hand.diceDescription() + "\n")

            let optimalDiceRoll = Score.calculateOptimal(forHand: hand)
            let maximizeDiceRoll = Score.calculateTotal(forHand: hand)

            if optimalDiceRoll.isFarkle {
                debugLog("❌ farkle")
                scoreThisTurn = 0
                doneRolling = true
            } else if maximizeDiceRoll.diceRemaining == 0 {
                // if all dice can get used, then use all the dice boi. 6 > 5 > 4 > 3 > 2 > 1...
                // so if you roll 2x 1s, don't leave 1 and farkle out, take both.
                // greedy or not, this is just "smart" strategy
                debugLog("😎 can take all dice and re-roll a full hand. YAY!:")
                debugLog("\(scoreThisTurn) + \(maximizeDiceRoll.points)")

                scoreThisTurn += maximizeDiceRoll.points
                hand.reset()
            } else if !self.greedy && (scoreThisTurn + maximizeDiceRoll.points >= requiredScoreThisTurnBeforeAllowedToEnd) && maximizeDiceRoll.diceRemaining < self.diceThreshold {
                // eg: if pt == 1000.. you're at 900... you roll 2 5s and 2 3s (aka not a zero-dice outcome), taking both 5s would breach the threshold.
                // A non-greedy player would say "oh goodie! By taking ALL of the dice, I breach my threshold and lock in my score."
                // But a greedy player would say "nope! Taking the least-dice-used route."
                debugLog("✅ A non-greedy player breaches their point AND dice threshold. ENDING TURN:")
                debugLog("\(scoreThisTurn) + \(maximizeDiceRoll.points)")
                scoreThisTurn += maximizeDiceRoll.points
                doneRolling = true
            } else if (scoreThisTurn + optimalDiceRoll.value) >= requiredScoreThisTurnBeforeAllowedToEnd {
                // eg: if pt == 1000.. you're at 900... you roll 2 1s and 2 3s (aka not a zero-dice outcome), taking even just one 1 would breach the threshold.
                // Both greedy and non-greedy need to then decide "okay. now that my point threshold has been broken by the most optimal dice roll, should i roll again or call it quits here?"

                debugLog("⚠️ point breached on optimal roll")

                // it is, however, likely that the non-greedy players will ALWAYS roll another as the check to see if they can "bounce early" has already been decided that it is not the case.
                // for greedy players, they'll ALWAYS want to roll again... unless of course the dice threshold is also breached. In which case their turn ends.
                if hand.dice.count - optimalDiceRoll.amountOfDice < self.diceThreshold {
                    debugLog("✅ optimal dice breached. ENDING TURN:")
                    debugLog("\(scoreThisTurn) + \(maximizeDiceRoll.points)")
                    scoreThisTurn += maximizeDiceRoll.points
                    doneRolling = true
                } else {
                    debugLog("🤞🏻 Taking optimal & rolling another:")
                    debugLog("\(scoreThisTurn) + \(optimalDiceRoll.value)")
                    scoreThisTurn += optimalDiceRoll.value // can roll another round since dice threshold not reached
                    hand.removeDice(for: optimalDiceRoll)
                }
            } else {
                // In this final case, the dice remaining is > 0
                // AND the point threshold was not breached from any method.
                // Which means the only thing left would be to take the optimal-dice route and re-roll.
                debugLog("🤞🏻 neither breached. Rolling again:")
                debugLog("\(scoreThisTurn) + \(optimalDiceRoll.value)")
                scoreThisTurn += optimalDiceRoll.value // can roll another around since point threshold not reached
                hand.removeDice(for: optimalDiceRoll)
            }
        }

        debugLog("\n💰 total score this turn: \(scoreThisTurn)")
        scoreboard?.lock(in: scoreThisTurn, for: self)
    }

    func takeFinalTurn(competingWithTopScore topScore: Int) {
        let delta = (topScore - self.score) + 50 // because you need to score HIGHER in order to be considered a winner.
        let previousPointThreshold = self.pointThreshold
        self.pointThreshold = self.playsFinalTurnDifferently ? delta : previousPointThreshold
        self.takeTurn()
        self.pointThreshold = previousPointThreshold
    }

    static func == (lhs: Player, rhs: Player) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
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
    static func calculateOptimal(forHand hand: Hand) -> Score {
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
        var score = calculateOptimal(forHand: tempHand)
        var totalScore = score.value

        while !score.isFarkle {
            tempHand.removeDice(for: score)
            score = calculateOptimal(forHand: tempHand)
            totalScore += score.value
        }

        return (points: totalScore, diceRemaining: tempHand.dice.count)
    }
}

protocol ScoreManager: AnyObject {
    func score(for player: Player) -> Int?
    func lock(in value: Int, for player: Player)
}

final class Game: ScoreManager {
    private(set) var players: [Player]
    private(set) var scores = [Player: Int]()

    private(set) var possibleWinner: Player?

    let minimumWinScore: Int
    var requiredToGetOnTheBoard: Int {
        didSet {
            players.forEach {
                $0.requiredToGetOnTheBoard = self.requiredToGetOnTheBoard
            }
        }
    }

    private(set) var numberOfRoundsPlayed = 0

    init?(with players: [Player], minimumWinScore: Int = 10000, requiredToGetOnTheBoard: Int = 500) {
        guard players.count >= 1 else {
            return nil
        }

        self.minimumWinScore = minimumWinScore
        self.requiredToGetOnTheBoard = requiredToGetOnTheBoard
        self.players = players
        self.players.forEach { player in
            player.requiredToGetOnTheBoard = self.requiredToGetOnTheBoard
            player.scoreboard = self
        }

        players.forEach {
            self.scores[$0] = 0
        }
    }

    func score(for player: Player) -> Int? {
        scores[player]
    }

    func lock(in value: Int, for player: Player) {
        scores[player]? += value
    }

    func playGame() {
        while self.possibleWinner == nil {
            self.playRound()
        }

        // one final round for everyone else, now that the possible winner is no longer in the "list" of rollers
        self.finalRound()

        //isLoggingEnabled = true

        if let winner = self.possibleWinner {
            debugLog("\n\n🎉\n\nAND WE HAVE A WINNER!!!")
            debugLog("after \(self.numberOfRoundsPlayed) rounds:")
            debugLog(winner.fullDescription)
            debugLog(self.rankDescription())
        }
    }

    func rankDescription() -> String {
        "\nRANKING:\n" + players.sorted { $0.score > $1.score }.map { "\($0.description): \($0.score)" }.joined(separator: "\n")
    }

    private func playRound() {
        self.numberOfRoundsPlayed += 1
        let roundString = "================ ROUND \(self.numberOfRoundsPlayed) ======================"
        debugLog("\n" + String(repeating: "=", count: roundString.count))
        debugLog(roundString)
        debugLog(String(repeating: "=", count: roundString.count))

        for _ in 0 ..< self.players.count {
            let player = self.players.remove(at: 0)
            debugLog("\n\n😊 Player \(player.description) taking turn #\(self.numberOfRoundsPlayed): \(player.score)\n")
            player.takeTurn()
            self.players.append(player)

            if player.score >= self.minimumWinScore {
                self.possibleWinner = player
                debugLog("\nPLAYER \(player.description) ENDED WITH SCORE \(player.score)")
                return // commence final round
            }
        }
    }

    private func finalRound() {
        guard players.count > 1 else {
            return
        }

        debugLog("\n===============================================")
        debugLog("================ FINAL ROUND ==================")
        debugLog("===============================================")

        // ignoring the final player since they started the final round
        for x in 0 ..< players.count - 1 {
            let player = players[x]
            debugLog("\n\nPlayer \(player.description) taking final turn: \(player.score)\n")
            player.takeFinalTurn(competingWithTopScore: possibleWinner?.score ?? minimumWinScore)

            if let currentWinner = possibleWinner, player.score > currentWinner.score {
                possibleWinner = player
            }

            if let currentWinner = possibleWinner, player.score > currentWinner.score {
                possibleWinner = player
            }

            debugLog("\nPLAYER \(player.description) ENDED WITH SCORE \(player.score)")
        }
    }
}

final class PlayerAnalyzer {
    private var player: Player

    private var games = [Game]()
    private var totalTurns = 0
    private var averageNumberOfTurnsToVictory: Double {
        Double(self.totalTurns) / Double(self.games.count)
    }

    init(player: Player) {
        self.player = player
    }

    func analyzeSinglePlayer(game: Game) {
        self.games.append(game)
        self.totalTurns += game.numberOfRoundsPlayed
    }

    func results() -> String {
        let allTurns = self.games.map { "\($0.numberOfRoundsPlayed)" }.joined(separator: ", ")
        return "All turns:\n" + allTurns + "\nAverage # until 10k:\n" + self.averageTurnsFormatted
    }

    var averageTurnsFormatted: String {
        String(format: "%.2f", self.averageNumberOfTurnsToVictory.round(to: 2))
    }

    var turnsStandardDeviation: String {
        String(format: "%.2f", self.games.map { Double($0.numberOfRoundsPlayed) }.standardDeviation())
    }
}

final class MultiGameAnalyzer {
    private var players: [Player]
    private var winCounter = [Player: Int]()
    private var games = [Game]()

    init(players: [Player]) {
        self.players = players
        self.players.forEach {
            self.winCounter[$0] = 0
        }
    }

    func analyze(game: Game) {
        self.games.append(game)
        if let winner = game.possibleWinner {
            self.winCounter[winner]? += 1
        }
    }

    func results() -> String {
        let headers = "Player ID, Point Threshold, Dice Threshold, Greedy, Plays Final Different, Win Count, Win Rate"
        let resultsTable = self.winCounter.map { player, winCount in
            let winRate = Double(winCount) / Double(self.games.count)
            let formattedWinRate = String(format: "%.2f", winRate.round(to: 2))
            return "\(player.description), \(player.pointThreshold), \(player.diceThreshold), \(player.greedy), \(player.playsFinalTurnDifferently), \(winCount), \(formattedWinRate)"
        }.joined(separator: "\n")

        return headers + "\n" + resultsTable
    }
}

enum Simulation {
    static func runSingleGames(forPlayers players: [Player], totalSimulatedRuns: Int, debugLoggingEnabled shouldLogThis: Bool = false) {
        let tempLogging = isLoggingEnabled
        isLoggingEnabled = shouldLogThis

        print("\n==== SOLO GAMES ====\n")

        let headers = "Player ID, Point Threshold, Dice Threshold, Greedy, Plays Final Different, average # till 10k, Std. Deviation"
        print(headers)

        players.forEach {
            let analyzer = PlayerAnalyzer(player: $0)

            /// for each "player" i want to run `totalSimulations` # of games
            for _ in 1...totalSimulatedRuns {
                if let session = Game(with: [$0]) {
                    session.playGame()

                    analyzer.analyzeSinglePlayer(game: session)
                }
            }

            print("\($0.description): \($0.pointThreshold), \($0.diceThreshold), \($0.greedy), \($0.playsFinalTurnDifferently), \(analyzer.averageTurnsFormatted), \(analyzer.turnsStandardDeviation)")
        }

        isLoggingEnabled = tempLogging
    }

    static func runMegaGames(forPlayers players: [Player], totalSimulatedRuns: Int, debugLoggingEnabled shouldLogThis: Bool = false) {
        let tempLogging = isLoggingEnabled
        isLoggingEnabled = shouldLogThis

        print("\n==== MEGA GAME ====\n")

        let analyzer = MultiGameAnalyzer(players: players)

        /// for each "player" i want to run `totalSimulations` # of games
        for _ in 1...totalSimulatedRuns {
            if let session = Game(with: players) {
                session.playGame()

                analyzer.analyze(game: session)
            }
        }

        print(analyzer.results())

        isLoggingEnabled = tempLogging
    }
}

enum BooleanVariant {
    case yes
    case no
}

enum Utility {
    static func generatePlayers(lowerPoint: Int, upperPoint: Int, greedyVariants: [BooleanVariant] = [.yes, .no],
                                finalVariants: [BooleanVariant] = [.yes]) -> [Player] {
        var variations = [PlayerVariation]()

        for pointThreshold in stride(from: lowerPoint, through: upperPoint, by: 50) {
            for diceThreshold in 2...6 {
                if greedyVariants.contains(.yes) {
                    if finalVariants.contains(.yes) {
                        variations.append(PlayerVariation(point: pointThreshold, dice: diceThreshold, greedy: true, final: true))
                    }

                    if finalVariants.contains((.no)) {
                        variations.append(PlayerVariation(point: pointThreshold, dice: diceThreshold, greedy: true, final: false))
                    }
                }

                if greedyVariants.contains(.no) {
                    if finalVariants.contains(.yes) {
                        variations.append(PlayerVariation(point: pointThreshold, dice: diceThreshold, greedy: false, final: true))
                    }

                    if finalVariants.contains((.no)) {
                        variations.append(PlayerVariation(point: pointThreshold, dice: diceThreshold, greedy: false, final: false))
                    }
                }
            }
        }

        return variations.map(Player.init)
    }
}

let players = Utility.generatePlayers(lowerPoint: 50, upperPoint: 300)

Simulation.runSingleGames(forPlayers: players, totalSimulatedRuns: 20)
//Simulation.runMegaGames(forPlayers: players, totalSimulatedRuns: 100)






// EXTRA STUFF:

/// Using `calculateOptimal(forHand:)`
/// Average for 6 dice rolling, over 10k rolls: 299 - 330
/// Average for 5 dice rolling, over 10k rolls: 156
/// Average for 4 dice rolling, over 10k rolls: 98
/// Average for 3 dice rolling, over 10k rolls: 66
/// Average for 2 dice rolling, over 10k rolls: 43
/// Average for 1 die rolling, over 10k rolls: 25
/// eg:

// var hand = Hand(count: 5)
// var runs = 10000
// var total = 0
// for _ in 1...runs {
//     hand.roll()
//     debugLog(hand.diceDescription())
//     total += Score.calculateOptimal(forHand: hand).value
// }
// debugLog(Double(total)/Double(runs))


/// Using `calculateTotal(forHand:)`
/// Average for 6 dice rolling, over 10k rolls: ???
/// Average for 5 dice rolling, over 10k rolls: ???
/// Average for 4 dice rolling, over 10k rolls: ???
/// Average for 3 dice rolling, over 10k rolls: ???
/// Average for 2 dice rolling, over 10k rolls: ???
/// Average for 1 die rolling, over 10k rolls: ???
/// eg:

// var hand = Hand(count: 5)
// var runs = 10000
// var total = 0
// for _ in 1...runs {
//     hand.roll()
//     debugLog(hand.diceDescription())
//     total += Score.calculateTotal(forHand: hand).points
// }
// debugLog(Double(total)/Double(runs))
