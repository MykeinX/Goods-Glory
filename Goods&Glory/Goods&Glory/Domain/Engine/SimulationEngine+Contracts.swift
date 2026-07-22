//
//  SimulationEngine+Contracts.swift
//  Goods&Glory
//
//  Contracts as commitments over existing lanes: offer generation, the
//  posting calendar, coverage, brief and the commitment ledger.
//

import Foundation

extension SimulationEngine {
    // MARK: - Contracts

    /// How far the company has grown. Purely derived from state, so it never
    /// needs saving and never drifts. Gates which archetypes the market offers
    /// and how large a cycle volume a customer dares to ask for.
    func companyTier(_ state: GameState) -> Int {
        let vehicles = state.vehicles.count
        let warehouses = state.facilities.compactMap {
            $0.operationalModule(.warehouse, at: state.clock)
        }
        let bigWarehouses = warehouses.filter { $0.level >= 2 }
        if vehicles > 30, !bigWarehouses.isEmpty { return 4 }
        if vehicles >= 11, !warehouses.isEmpty { return 3 }
        if vehicles >= 4 || state.stats.deliveredJobs >= 40 { return 2 }
        return 1
    }

    func archetypes(forTier tier: Int) -> [ContractArchetype] {
        var available: [ContractArchetype] = [.laneRecurring]
        if tier >= 2 { available.append(.evergreen) }
        if tier >= 3 { available.append(.bulkPeriodic) }
        if tier >= 4 { available.append(.multiDrop) }
        return available
    }

    /// How many contract lanes one branch city keeps on the table. Contracts
    /// are not a scarcity game — the scarce thing is the branch investment, so
    /// a branch city always shows a workable menu, scaled by its own market.
    func contractSlots(in cityID: CityID, state: GameState) -> Int {
        guard let city = catalog.city(cityID),
              let office = state.facility(in: cityID)?.operationalModule(.office, at: state.clock),
              let quote = quote(kind: .office, level: office.level, city: cityID) else { return 0 }
        let insight = CityInsight.make(city: city, catalog: catalog)
        let base = 3 + 6 * insight.marketSizePercent
        return max(2, Int((base * quote.contractSlotFactor).rounded()))
    }

    // MARK: Lane commitment

    /// Smallest slice of a lane worth writing a contract over.
    static let minimumCommitmentBps = 1_500

    /// How much of one lane a shipper will hand to a company of this size.
    /// Growing the company is what unlocks the bigger commitments — and with
    /// them the volumes that force a hub network.
    static func commitmentCeilingBps(forTier tier: Int) -> Int {
        switch tier {
        case 1: 3_000
        case 2: 5_000
        case 3: 7_500
        default: ContractDestination.fullShareBps
        }
    }

    /// A little more than the company has proven it can carry. Room to grow
    /// into, not a leap of faith.
    static let relationshipStretch = 1.25

    /// How much of a lane's output the company has actually been carrying,
    /// in basis points of the lane's daily rate.
    ///
    /// This is the relationship. A contract is a firm reserving part of its
    /// production for a carrier — nobody does that for a company they have
    /// never seen. Offers used to be drawn from every lane out of any branch
    /// city, so the board filled with commitments on lanes the player had never
    /// driven, and signing one was a blind bet that instantly became a penalty.
    func servedShareBps(of lane: FreightLane, state: GameState) -> Int {
        let delivered = state.stats.deliveredKgByLane[lane.id] ?? 0
        guard delivered > 0, lane.baseRatePerDayKg > 0 else { return 0 }
        // Measured against what the lane produced while the company existed, so
        // an old lane served briefly does not read as a deep relationship.
        let days = max(1.0, Double(state.clock.totalMinutes) / Double(GameState.minutesPerDay))
        let produced = Double(lane.baseRatePerDayKg) * days
        let share = min(1.0, Double(delivered) / produced)
        return Int((share * Double(ContractDestination.fullShareBps)).rounded())
    }

    /// The most a firm on this lane would hand over right now: a bit beyond the
    /// share the company already moves, and never more than the tier allows.
    func relationshipCeilingBps(of lane: FreightLane, tier: Int, state: GameState) -> Int {
        let served = Double(servedShareBps(of: lane, state: state))
        return min(
            Self.commitmentCeilingBps(forTier: tier),
            Int((served * Self.relationshipStretch).rounded())
        )
    }

    /// Share of a lane not already promised to a signed contract or a standing
    /// offer. Offers count so two open lanes cannot both sell the same tonnage.
    func uncommittedShareBps(of laneID: LaneID, state: GameState) -> Int {
        var committed = 0
        for contract in state.activeContracts {
            for destination in contract.destinations where destination.laneID == laneID {
                committed += destination.committedShareBps
            }
        }
        for offer in state.contractOffers {
            for destination in offer.destinations where destination.laneID == laneID {
                committed += destination.committedShareBps
            }
        }
        return max(0, ContractDestination.fullShareBps - committed)
    }

    /// What a lane's firms will still commit, all together.
    ///
    /// The per-offer ceiling was not enough: four separate offers on the same
    /// lane each sat inside the relationship ceiling and together locked 91% of
    /// it, which no fleet that also lifts spot freight off the same dock can
    /// serve. A shipper's trust is a total, not a per-contract allowance.
    func openShareBps(of lane: FreightLane, tier: Int, state: GameState) -> Int {
        let free = uncommittedShareBps(of: lane.id, state: state)
        let trust = relationshipCeilingBps(of: lane, tier: tier, state: state)
        let alreadyCommitted = ContractDestination.fullShareBps - free
        return max(0, min(free, trust - alreadyCommitted))
    }

    /// Share of a lane's daily rate already locked into signed contracts. This
    /// tonnage is posted as contract parcels, so it must not also accrue at the
    /// dock as spot freight.
    func committedShareBps(of laneID: LaneID, state: GameState) -> Int {
        var committed = 0
        for contract in state.activeContracts where !contract.isClosing(at: state.clock) {
            for destination in contract.destinations where destination.laneID == laneID {
                committed += destination.committedShareBps
            }
        }
        return min(ContractDestination.fullShareBps, committed)
    }

    /// Premium a commitment pays over the same parcel's spot rate. Big markets
    /// pay better; crowded markets squeeze. One formula, so competitors later
    /// change only `competitionPercent` and every price follows.
    func contractPremium(origin: CityID, destination: CityID) -> Double {
        let base = Double(catalog.economy.contractPremiumPercent) / 100
        guard let city = catalog.city(origin) else { return base }
        let insight = CityInsight.make(city: city, catalog: catalog)
        let demandBonus = 1 + 0.35 * insight.marketSizePercent
        let competitionSqueeze = 1 - 0.30 * insight.competitionPercent
        return base * demandBonus * competitionSqueeze
    }

    /// Advances the batch clock. The board refill itself is not tied to this
    /// tick — see `replenishContractOffers`.
    func generateContractOfferBatch(state: inout GameState) {
        state.nextContractBatchAt = state.nextContractBatchAt
            + catalog.economy.contractOfferIntervalMinutes
        replenishContractOffers(state: &state)
    }

    /// Refills every branch city's contract board to its slot count. Runs on
    /// the event loop rather than only on the daily tick, so signing a lane or
    /// a batch of offers ageing out cannot leave a branch showing an empty
    /// board until the next morning.
    func replenishContractOffers(state: inout GameState) {
        let interval = catalog.economy.contractOfferIntervalMinutes
        // One generation attempt per slot per interval keeps the board stocked
        // without minting a fresh lane every simulated minute.
        let batchIndex = state.clock.totalMinutes / max(1, interval)
        let generatedAt = state.clock

        let referenceTypes: [VehicleTypeDefinition] = {
            let owned = state.vehicles.compactMap { catalog.vehicleType($0.typeID) }
            if !owned.isEmpty { return owned }
            if let entry = catalog.vehicleTypes
                .filter({ $0.purchasePrice <= state.cash })
                .min(by: { $0.purchasePrice < $1.purchasePrice }) {
                return [entry]
            }
            return Array(catalog.vehicleTypes.prefix(1))
        }()
        // The biggest class the company can actually run is the parcel ceiling:
        // picking a random owned class made the same lane offer different parcel
        // sizes from one refill to the next for no reason the player could see.
        guard let ceilingType = referenceTypes.max(by: {
            $0.capacity.massKg < $1.capacity.massKg
        }) else { return }

        // Shippers do not hand recurring volume to a company that has never
        // moved anything. The first days are spot work; contracts are what the
        // player graduates into once they have proven they can deliver.
        guard state.stats.deliveredJobs >= catalog.economy.contractsUnlockAfterDeliveries else { return }

        let tier = companyTier(state)
        let available = archetypes(forTier: tier)

        // Open lanes counted once for the whole board rather than rescanning it
        // per city. Safe to cache: every offer appended below belongs to the
        // origin currently being processed, and each origin is visited once.
        var openByOrigin: [CityID: Int] = [:]
        for offer in state.contractOffers { openByOrigin[offer.origin, default: 0] += 1 }

        // Contract business exists only where the company has a branch, and a
        // branch city's board is never allowed to sit empty: whatever emptied
        // it — expiry, signing, a demolished rival branch — the next pass tops
        // it straight back up. Having a branch *is* the standing entitlement to
        // see work, independent of where the fleet happens to be parked.
        for origin in state.contractCities.sorted(by: { $0.rawValue < $1.rawValue }) {
            let slots = contractSlots(in: origin, state: state)
            let open = openByOrigin[origin, default: 0]
            guard open < slots else { continue }

            for slot in open..<slots {
                var rng = SeededRNG(seed: SeedDerivation.seed(
                    state.config.seed,
                    "contract_batch",
                    .int(batchIndex),
                    .string(origin.rawValue),
                    .int(slot)
                ))
                guard let archetype = available.randomElement(using: &rng),
                      let offer = makeContractOffer(
                        archetype: archetype,
                        origin: origin,
                        referenceType: ceilingType,
                        tier: tier,
                        generatedAt: generatedAt,
                        state: &state,
                        rng: &rng
                      ) else { continue }
                state.contractOffers.append(offer)
            }
        }
    }

    func makeContractOffer(
        archetype: ContractArchetype,
        origin: CityID,
        referenceType: VehicleTypeDefinition,
        tier: Int,
        generatedAt: GameTime,
        state: inout GameState,
        rng: inout SeededRNG
    ) -> ContractOffer? {
        // A contract is written on top of freight that already moves. The
        // shipper is not inventing a lane for the player — they are offering
        // to commit part of what their firm ships anyway, which is why the
        // offer starts from a lane rather than from a product and a map.
        // Only lanes the company already hauls, and only as far as its record
        // on them justifies. This is what makes a contract feel earned rather
        // than dealt: you drive a lane well, the firm on it offers to reserve
        // part of its output for you, and the better you serve it the more of
        // it they are willing to commit.
        let candidates = catalog.lanes(from: origin).filter { lane in
            openShareBps(of: lane, tier: tier, state: state) >= Self.minimumCommitmentBps
        }
        guard !candidates.isEmpty else { return nil }

        // Multi-drop needs several lanes out of the same city, one per drop.
        let dropCount = archetype == .multiDrop ? min(candidates.count, Int.random(in: 2...3, using: &rng)) : 1
        var chosenLanes: [FreightLane] = []
        for _ in 0..<dropCount {
            let remaining = candidates.filter { lane in
                !chosenLanes.contains { $0.id == lane.id }
                    && !chosenLanes.contains { $0.destinationCityID == lane.destinationCityID }
            }
            // Weighted by rate *and* by how much of it the company already
            // hauls: the firm you serve most is the one that offers first.
            let weighted = remaining.map { lane in
                (lane, Double(lane.baseRatePerDayKg)
                    * (1 + Double(servedShareBps(of: lane, state: state)) / 5_000))
            }
            guard let picked = weightedPick(weighted, rng: &rng) else { break }
            chosenLanes.append(picked)
        }
        guard let primary = chosenLanes.first,
              let product = catalog.product(primary.productID) else { return nil }
        // One product per contract: the parcel size and the truck class are
        // sized for it, and mixing goods would make both meaningless.
        chosenLanes = chosenLanes.filter { $0.productID == primary.productID }

        struct Leg {
            let lane: FreightLane
            let distanceKm: Double
            let cycleMinutes: Int
            let committedShareBps: Int
            let dailyKg: Int
        }
        var legs: [Leg] = []
        for lane in chosenLanes {
            guard let distanceKm = catalog.roadDistanceKm(
                from: origin, to: lane.destinationCityID
            ) else { continue }
            // How much of this lane the shipper is willing to hand over: what
            // is still free, capped by the company's size and by how much of
            // this particular lane it has been carrying.
            let ceiling = openShareBps(of: lane, tier: tier, state: state)
            guard ceiling >= Self.minimumCommitmentBps else { continue }
            let share = Int.random(in: Self.minimumCommitmentBps...ceiling, using: &rng)
            let cycleMinutes = contractCycleMinutes(
                origin: origin,
                destination: lane.destinationCityID,
                distanceKm: distanceKm,
                vehicleType: referenceType
            )
            legs.append(Leg(
                lane: lane,
                distanceKm: distanceKm,
                cycleMinutes: cycleMinutes,
                committedShareBps: share,
                dailyKg: lane.baseRatePerDayKg * share / ContractDestination.fullShareBps
            ))
        }
        guard !legs.isEmpty, legs.allSatisfy({ $0.dailyKg > 0 }) else { return nil }
        let longestCycleMinutes = legs.map(\.cycleMinutes).max() ?? 0
        guard longestCycleMinutes > 0 else { return nil }

        // Cadence is free to choose; volume is not. The committed share of the
        // lane over one interval *is* the cycle volume, so a contract can never
        // ask for freight the world does not produce.
        let dailyTotalKg = legs.reduce(0) { $0 + $1.dailyKg }
        guard dailyTotalKg > 0 else { return nil }
        // A cadence has to be long enough to accumulate something worth
        // sending. A lane moving 300 kg a day cannot promise a daily truck —
        // it promises a smaller load, less often. Without this the whole
        // contract board silently vanishes on modest lanes.
        let minimumDaysPerParcel = max(
            1,
            (product.minimumShipmentMassKg + dailyTotalKg - 1) / dailyTotalKg
        )
        let interval = max(
            shipmentInterval(archetype: archetype, cycleMinutes: longestCycleMinutes, rng: &rng),
            minimumDaysPerParcel * GameState.minutesPerDay
        )
        let intervalDays = Double(interval) / Double(GameState.minutesPerDay)
        let volumePerCycleKg = legs.reduce(0) { $0 + Int((Double($1.dailyKg) * intervalDays).rounded()) }

        // Parcel size follows the freight, not the truck: the reference class
        // is a ceiling, never a floor. Sizing the other way round is what made
        // small lanes un-contractable.
        guard let parcel = parcelSize(
            product: product,
            capacity: referenceType.capacity,
            cycleVolumeKg: volumePerCycleKg,
            dropCount: legs.count
        ) else { return nil }

        // The class that *prices* the parcel is the smallest one it fits in,
        // not whichever truck happens to be in the garage. Pricing bills the
        // share of a vehicle the load uses, with a floor — so quoting a two
        // tonne parcel against a semi charged the shipper half a lorry and
        // made the same freight worth more to a company that owned bigger
        // trucks. The reference class stays the parcel-size ceiling; it stops
        // being the price basis.
        let pricingType = catalog.vehicleTypes
            .filter { parcel.fits(in: $0.capacity) }
            .min { $0.capacity.massKg < $1.capacity.massKg }
            ?? referenceType

        // Shares are whole basis points and must total exactly 10 000, so the
        // posted volume never silently drifts from the agreed volume.
        var destinations: [ContractDestination] = []
        var assignedBps = 0
        for (index, leg) in legs.enumerated() {
            let isLast = index == legs.count - 1
            let share = isLast
                ? ContractDestination.fullShareBps - assignedBps
                : Int((Double(leg.dailyKg) / Double(legs.reduce(0) { $0 + $1.dailyKg })
                    * Double(ContractDestination.fullShareBps)).rounded())
            assignedBps += share
            // Price from the lane's own spot rate: a commitment pays a premium
            // over what the same parcel earns unsigned, which is what makes
            // signing worth the SLA and the penalty that come with it.
            let spot = freightPayout(
                origin: origin,
                destination: leg.lane.destinationCityID,
                distanceKm: leg.distanceKm,
                load: parcel,
                vehicleType: pricingType,
                state: state
            )
            let premium = contractPremium(origin: origin, destination: leg.lane.destinationCityID)
            destinations.append(ContractDestination(
                cityID: leg.lane.destinationCityID,
                firmID: leg.lane.destinationFirmID,
                laneID: leg.lane.id,
                committedShareBps: leg.committedShareBps,
                shareBps: share,
                distanceKm: leg.distanceKm,
                payoutPerParcel: Money(max(1, (Double(spot) * (1 + premium)).rounded()))
            ))
        }

        return ContractOffer(
            id: ContractID(rawValue: state.issueID()),
            origin: origin,
            productID: primary.productID,
            archetype: archetype,
            destinations: destinations,
            referenceVehicleTypeID: pricingType.id,
            parcelMassKg: parcel.massKg,
            volumePerCycleKg: volumePerCycleKg,
            shipmentIntervalMinutes: interval,
            deliveryWindowMinutes: deliveryWindow(cycleMinutes: longestCycleMinutes, interval: interval),
            leadTimeMinutes: leadTime(cycleMinutes: longestCycleMinutes),
            durationDays: contractDuration(archetype: archetype, rng: &rng),
            originFirmID: primary.originFirmID,
            createdAt: generatedAt,
            // Staggered on purpose. Topping the board up to N means one cohort
            // is created together, and a fixed lifetime would then retire the
            // whole board in the same minute — which is exactly the "all the
            // contracts vanished at once" the branch screen was showing. Random
            // lifetimes turn that cliff into steady rotation.
            expiresAt: generatedAt
                + catalog.economy.contractOfferIntervalMinutes * Int.random(in: 2...6, using: &rng)
        )
    }

    /// Cadence between posted cycles, always a whole number of days so the
    /// player can plan around a readable rhythm.
    func shipmentInterval(
        archetype: ContractArchetype,
        cycleMinutes: Int,
        rng: inout SeededRNG
    ) -> Int {
        // Never tighter than one cycle: a cadence the reference vehicle cannot
        // physically meet is a trap, not a challenge.
        let minimumDays = max(1, (cycleMinutes + GameState.minutesPerDay - 1) / GameState.minutesPerDay)
        let days: Int = switch archetype {
        case .laneRecurring, .evergreen:
            minimumDays + Int.random(in: 0...1, using: &rng)
        case .multiDrop:
            max(2, minimumDays + Int.random(in: 1...2, using: &rng))
        case .bulkPeriodic:
            // Weekly or fortnightly drumbeat: enough runway to stage a fleet.
            max(minimumDays, Int.random(in: 7...14, using: &rng))
        }
        return days * GameState.minutesPerDay
    }

    /// Time a posted parcel has before it counts as late. Deliberately not the
    /// shipment interval: a daily lane over 800 km would be impossible to serve.
    func deliveryWindow(cycleMinutes: Int, interval: Int) -> Int {
        let fromCycle = Int(
            Double(cycleMinutes) * Double(catalog.economy.contractDeliveryWindowPercent) / 100
        )
        let floor = Int(
            Double(interval) * Double(catalog.economy.contractDeliveryWindowFloorPercent) / 100
        )
        return max(60, max(fromCycle, floor))
    }

    /// Preparation time between signing and the first posted cycle, so the
    /// player can position vehicles instead of being caught mid-network.
    func leadTime(cycleMinutes: Int) -> Int {
        max(60, Int(Double(cycleMinutes) * Double(catalog.economy.contractLeadTimePercent) / 100))
    }

    func contractDuration(archetype: ContractArchetype, rng: inout SeededRNG) -> Int? {
        switch archetype {
        case .evergreen:
            return nil
        case .laneRecurring:
            return catalog.economy.contractDurationDays * Int.random(in: 1...3, using: &rng)
        case .multiDrop, .bulkPeriodic:
            return catalog.economy.contractDurationDays * Int.random(in: 2...6, using: &rng)
        }
    }

    func postDueContractShipments(state: inout GameState) {
        for index in state.activeContracts.indices {
            while state.activeContracts[index].nextShipmentAt <= state.clock,
                  !state.activeContracts[index].isClosing(at: state.clock) {
                postContractCycle(contractIndex: index, state: &state)
            }
        }
    }

    /// Minutes for one full contract cycle with the given vehicle class:
    /// load at origin, drive loaded, unload at destination, drive back empty.
    func contractCycleMinutes(
        origin: CityID,
        destination: CityID,
        distanceKm: Double,
        vehicleType: VehicleTypeDefinition
    ) -> Int {
        let oneWay = travelMinutes(distanceKm: distanceKm, speedKmh: vehicleType.speedKmh)
        return loadingMinutes(at: origin) + oneWay + unloadingMinutes(at: destination) + oneWay
    }

    /// Posts one full cycle: the agreed volume split into vehicle-sized parcels
    /// across every destination. A bulk contract posts many parcels at once —
    /// that is precisely the pressure that makes a hub network worth building.
    func postContractCycle(contractIndex: Int, state: inout GameState) {
        guard state.activeContracts.indices.contains(contractIndex) else { return }
        var contract = state.activeContracts[contractIndex]
        guard !contract.isClosing(at: state.clock) else { return }

        let deadline = state.clock + contract.deliveryWindowMinutes
        let minimumParcelKg = catalog.product(contract.productID)?.minimumShipmentMassKg ?? 0
        for destination in contract.destinations {
            var remaining = contract.cycleVolume(for: destination)
            while remaining > 0 {
                let massKg = min(remaining, contract.parcelMassKg)
                // A crumb is not a consignment. A cycle that divided into 4.2 t
                // plus 47 kg posted that 47 kg as a parcel of its own — a load
                // nobody sends a truck for, which then aged out and drew a
                // penalty every single cycle. Below the product's minimum
                // shipment the remainder is simply not shipped; it cannot be
                // folded into the last parcel either, because a parcel sized to
                // exactly fill the reference truck would then never fit in one.
                guard massKg >= minimumParcelKg else { break }
                remaining -= massKg
                // Partial parcels pay pro rata: half a load earns half the fee.
                let payout = contract.parcelMassKg > 0
                    ? Money(
                        (Double(destination.payoutPerParcel) * Double(massKg)
                            / Double(contract.parcelMassKg)).rounded()
                      )
                    : destination.payoutPerParcel
                state.offers.append(JobOffer(
                    id: JobID(rawValue: state.issueID()),
                    origin: contract.origin,
                    destination: destination.cityID,
                    productID: contract.productID,
                    load: parcelLoad(productID: contract.productID, massKg: massKg),
                    payout: max(1, payout),
                    distanceKm: destination.distanceKm,
                    urgency: .normal,
                    source: .contract,
                    contractID: contract.id,
                    // The parcel remembers which lane it was carved out of.
                    // Without this a route already serving that lane could not
                    // recognise its own committed freight, so signing a contract
                    // for freight you were already hauling made the board shout
                    // "nothing is carrying this".
                    laneID: destination.laneID,
                    originFirmID: contract.originFirmID,
                    destinationFirmID: destination.firmID,
                    createdAt: state.clock,
                    expiresAt: deadline
                ))
                contract.shipmentsIssued += 1
            }
        }
        contract.nextShipmentAt = contract.nextShipmentAt + contract.shipmentIntervalMinutes
        state.activeContracts[contractIndex] = contract
    }

    /// Volume of a parcel derived from the product's density.
    func parcelLoad(productID: ProductID, massKg: Int) -> LoadSize {
        let density = catalog.product(productID)?.densityM3PerTon ?? 1
        let volumeM3 = (Double(massKg) / 1000 * density * 10).rounded() / 10
        return LoadSize(massKg: massKg, volumeM3: volumeM3)
    }

}

// MARK: - Contract lifecycle

extension SimulationEngine {
    func retireRoutes(ofEndedContract contractID: ContractID, state: inout GameState) {
        for route in state.routes {
            let mentionsContract = route.stops.contains { stop in
                switch stop.task {
                case .pickupContract(let id), .deliverContract(let id): id == contractID
                default: false
                }
            }
            guard mentionsContract else { continue }
            state.appendLog(.routeNeedsReview(routeID: route.id, contractID: contractID))
        }
    }

    /// Closes contracts that reached their term, and clears cancelled ones once
    /// their committed cargo has left the network. Closing never destroys
    /// freight: parcels already accepted keep running to their destination.
    func expireFinishedContracts(state: inout GameState) {
        // Which contracts still have cargo anywhere in the network, in one pass
        // over shipments and offers rather than one pass per contract. This
        // runs on every step of the advance loop, so the old
        // O(contracts × (shipments + offers)) shape dominated a large campaign.
        // Only built when something is actually winding down, which is rare.
        var committedContractIDs: Set<ContractID> = []
        if state.activeContracts.contains(where: { $0.cancellationRequestedAt != nil }) {
            for shipment in state.shipments {
                if let id = shipment.offer.contractID { committedContractIDs.insert(id) }
            }
            for offer in state.offers {
                if let id = offer.contractID { committedContractIDs.insert(id) }
            }
        }

        let clock = state.clock
        let finished = state.activeContracts.filter { contract in
            if let endsAt = contract.endsAt, endsAt <= clock { return true }
            // A cancelled contract lingers until nothing of it is left moving.
            guard contract.cancellationRequestedAt != nil else { return false }
            return !committedContractIDs.contains(contract.id)
        }
        guard !finished.isEmpty else { return }
        let finishedIDs = Set(finished.map(\.id))

        for contract in finished {
            // Unclaimed obligations at term end count as missed; already
            // accepted parcels are untouched and still pay on delivery.
            let leftover = state.offers.filter {
                $0.source == .contract && $0.contractID == contract.id
            }
            state.offers.removeAll { $0.source == .contract && $0.contractID == contract.id }
            for offer in leftover {
                chargeMissedShipment(offer: offer, state: &state)
            }
            let tally = state.activeContract(contract.id) ?? contract
            state.appendLog(.contractEnded(
                contractID: contract.id,
                completed: tally.shipmentsCompleted,
                missed: tally.shipmentsMissed
            ))
            retireRoutes(ofEndedContract: contract.id, state: &state)
        }
        state.activeContracts.removeAll { finishedIDs.contains($0.id) }
    }

}
