pub mod mods;

#[starknet::contract]
pub mod SPL {
    use openzeppelin_token::erc20::interface::ERC20ABISafeDispatcherTrait;
    use super::mods::{
        types::{
            Score, PredictionDetails, Leaderboard, Match, RoundDetails, MatchType, User, Prediction,
            PredictionType, RawPrediction, RawPredictionType, PredictionVariants, RawMatch, Team,
            UserPrediction, Odd
        },
        constants::Errors, interfaces::ispl::ISPL
    };
    use starknet::{
        storage::Map, class_hash::ClassHash, SyscallResultTrait, ContractAddress,
        get_caller_address, get_block_timestamp, get_contract_address
    };
    use core::{num::traits::Zero};

    use openzeppelin_token::{erc20::interface::{ERC20ABISafeDispatcher},};

    #[event]
    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub enum Event {
        Upgraded: Upgraded,
    }


    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub struct Upgraded {
        pub implementation: ClassHash
    }


    #[storage]
    struct Storage {
        total_users: u256,
        user: Map::<ContractAddress, User>,
        registered: Map::<ContractAddress, bool>,
        user_by_index: Map::<u256, User>,
        user_by_id: Map::<felt252, User>,
        version: u256,
        owner: ContractAddress,
        total_matches: u256,
        match_details: Map::<felt252, Match>,
        match_odds: Map::<(felt252, felt252), Odd>,
        match_index: Map::<felt252, u256>,
        match_ids: Map::<u256, felt252>,
        users_scores: Map::<(ContractAddress, felt252), u256>,
        predictions: Map::<(ContractAddress, felt252), Prediction>,
        prediction_ptr: Map::<felt252, Prediction>,
        prediction_pair: Map::<(felt252, u256), PredictionVariants>,
        prediction_pair_count: Map::<felt252, u256>,
        predicted: Map::<(ContractAddress, felt252), bool>,
        prediction_id_pointer: Map::<u256, felt252>,
        prediction_index_pointer: Map::<felt252, u256>,
        match_predictions_count: Map::<felt252, u256>,
        prediction_user_index_pointer: Map::<ContractAddress, u256>,
        prediction_user_id_pointer: Map::<u256, ContractAddress>,
        user_points: Map::<ContractAddress, u256>,
        user_prediction_count: Map::<ContractAddress, u256>,
        user_prediction_index_pointer: Map::<u256, felt252>,
        // user_match_predicted_ptr: Map
        current_round: u256,
        user_rewards: Map::<ContractAddress, u256>,
        round_details: Map::<u256, RoundDetails>,
        erc20_token: ContractAddress,
    }


    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, erc20_token: ContractAddress,) {
        self.owner.write(owner);
        self.erc20_token.write(erc20_token);
    }


    #[abi(embed_v0)]
    impl SPLImpl of ISPL<ContractState> {
        fn register_user(ref self: ContractState, user: User) {
            let caller = get_caller_address();
            assert(!self.registered.read(caller), Errors::ALREADY_EXIST);
            assert(user.address.is_non_zero(), Errors::INVALID_ADDRESS);
            assert(user.username.is_non_zero() && user.id.is_non_zero(), 'INVALID_PARAMS');
            assert(self.user_by_id.read(user.id).address.is_zero(), Errors::ALREADY_EXIST);
            self.registered.write(caller, true);
            self.user.write(caller, user);
            self.user_by_id.write(user.id, user);
            let total_users = self.total_users.read() + 1;
            self.user_by_index.write(total_users, user);
            self.total_users.write(total_users);
        }

        ///test function
        fn get_user_by_index(self: @ContractState, index: u256) -> User {
            self.user_by_index.read(index)
        }

        fn get_user_by_id(self: @ContractState, id: felt252) -> User {
            self.user_by_id.read(id)
        }


        fn is_address_registered(self: @ContractState, address: ContractAddress) -> bool {
            self.registered.read(address)
        }

        fn get_user_by_address(self: @ContractState, address: ContractAddress) -> User {
            self.user.read(address)
        }

        fn upgrade(ref self: ContractState, impl_hash: ClassHash) {
            assert(get_caller_address() == self.owner.read(), Errors::UNAUTHORIZED);
            assert(impl_hash.is_non_zero(), Errors::INVAliD_CLASSHASH);
            starknet::syscalls::replace_class_syscall(impl_hash).unwrap_syscall();
            self.version.write(self.version.read() + 1);
            self.emit(Event::Upgraded(Upgraded { implementation: impl_hash }));
        }

        fn update_erc20(ref self: ContractState, new_address: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), Errors::UNAUTHORIZED);
            assert(new_address.is_non_zero(), Errors::INVAliD_CLASSHASH);
            self.erc20_token.write(new_address);
        }


        fn make_prediction(ref self: ContractState, predictions: RawPrediction) {
            let caller = get_caller_address();
            assert(self.registered.read(caller), Errors::NOT_REGISTERED);

            match predictions.prediction_type {
                RawPredictionType::Single(val) => {
                    let _match = self.match_details.read(val.match_id);
                    assert(_match.inputed, Errors::INVALID_MATCH_ID);
                    assert(
                        _match.home.goals.is_none() && _match.away.goals.is_none(), 'MATCH_SCORED'
                    );
                    assert(!self.predicted.read((caller, val.match_id)), Errors::PREDICTED);
                    if let MatchType::Live = _match.match_type {
                        assert(
                            get_block_timestamp() + 600 < (_match.timestamp),
                            Errors::PREDICTION_CLOSED
                        );
                    } else {
                        assert(
                            get_block_timestamp() < (_match.timestamp), Errors::PREDICTION_CLOSED
                        );
                    }

                    let prediction_construct = Prediction {
                        stake: predictions.stake,
                        inputed: true,
                        prediction_type: PredictionType::Single(val),
                        odd: Option::Some(self.match_odds.read((val.match_id, val.odd)))
                        // pair: Option::None
                    };
                    self.predicted.write((caller, val.match_id), true);
                    self.predictions.write((caller, val.match_id), prediction_construct);

                    let match_predictions_count = self.match_predictions_count.read(val.match_id);

                    self.prediction_user_id_pointer.write(match_predictions_count + 1, caller);
                    self.prediction_user_index_pointer.write(caller, match_predictions_count + 1);
                    self.match_predictions_count.write(val.match_id, match_predictions_count + 1);
                    let user_prediction_count = self.user_prediction_count.read(caller);
                    self
                        .user_prediction_index_pointer
                        .write(user_prediction_count + 1, val.match_id);
                    self.user_prediction_count.write(caller, user_prediction_count + 1);
                },
                RawPredictionType::Multiple(val) => {
                    assert(predictions.pair.is_some(), 'INVALID_PARAMS');
                    // let mut prediction_pair = array![];
                    let mut pair_index = 0;
                    for _val in val {
                        let _match = self.match_details.read(_val.match_id);
                        assert(_match.inputed, Errors::INVALID_MATCH_ID);
                        assert(
                            _match.home.goals.is_none() && _match.away.goals.is_none(),
                            'MATCH_SCORED'
                        );
                        assert(!self.predicted.read((caller, _val.match_id)), Errors::PREDICTED);
                        if let MatchType::Live = _match.match_type {
                            assert(
                                get_block_timestamp() + 600 < (_match.timestamp),
                                Errors::PREDICTION_CLOSED
                            );
                        } else {
                            assert(
                                get_block_timestamp() < (_match.timestamp),
                                Errors::PREDICTION_CLOSED
                            );
                        }

                        self.predicted.write((caller, _val.match_id), true);
                        let match_predictions_count = self
                            .match_predictions_count
                            .read(_val.match_id);

                        self.prediction_user_id_pointer.write(match_predictions_count + 1, caller);
                        self
                            .prediction_user_index_pointer
                            .write(caller, match_predictions_count + 1);
                        self
                            .match_predictions_count
                            .write(_val.match_id, match_predictions_count + 1);
                        let user_prediction_count = self.user_prediction_count.read(caller);
                        self
                            .user_prediction_index_pointer
                            .write(user_prediction_count + 1, _val.match_id);
                        self.user_prediction_count.write(caller, user_prediction_count + 1);
                        let prediction_construct = Prediction {
                            stake: predictions.stake,
                            inputed: true,
                            prediction_type: PredictionType::Multiple(predictions.pair.unwrap()),
                            odd: Option::Some(self.match_odds.read((_val.match_id, _val.odd)))
                        };
                        self.predictions.write((caller, _val.match_id), prediction_construct);
                        pair_index += 1;
                        self.prediction_pair.write((predictions.pair.unwrap(), pair_index), _val);
                    };
                    self.prediction_pair_count.write(predictions.pair.unwrap(), pair_index);
                }
            }

            if predictions.stake > 0 {
                let erc20_dispatcher = ERC20ABISafeDispatcher {
                    contract_address: self.erc20_token.read()
                };
                erc20_dispatcher
                    .transfer_from(caller, get_contract_address(), predictions.stake)
                    .unwrap();
            }
        }


        fn make_bulk_prediction(ref self: ContractState, predictions: Array<RawPrediction>) {
            let caller = get_caller_address();
            assert(self.registered.read(caller), Errors::NOT_REGISTERED);
            let is_single_type = match predictions[0].prediction_type {
                RawPredictionType::Single(_) => true,
                _ => false
            };
            let mut total_stake = 0;
            for prediction in predictions {
                match prediction.prediction_type {
                    RawPredictionType::Single(val) => {
                        assert(is_single_type, 'INVALID_PARAMS');
                        let _match = self.match_details.read(val.match_id);
                        assert(_match.inputed, Errors::INVALID_MATCH_ID);
                        assert(
                            _match.home.goals.is_none() && _match.away.goals.is_none(),
                            'MATCH_SCORED'
                        );
                        assert(!self.predicted.read((caller, val.match_id)), Errors::PREDICTED);
                        if let MatchType::Live = _match.match_type {
                            assert(
                                get_block_timestamp() + 600 < (_match.timestamp),
                                Errors::PREDICTION_CLOSED
                            );
                        } else {
                            assert(
                                get_block_timestamp() < (_match.timestamp),
                                Errors::PREDICTION_CLOSED
                            );
                        }

                        let prediction_construct = Prediction {
                            stake: prediction.stake,
                            inputed: true,
                            prediction_type: PredictionType::Single(val),
                            odd: Option::Some(self.match_odds.read((val.match_id, val.odd)))
                            // pair: Option::None
                        };
                        self.predicted.write((caller, val.match_id), true);
                        self.predictions.write((caller, val.match_id), prediction_construct);

                        let match_predictions_count = self
                            .match_predictions_count
                            .read(val.match_id);

                        self.prediction_user_id_pointer.write(match_predictions_count + 1, caller);
                        self
                            .prediction_user_index_pointer
                            .write(caller, match_predictions_count + 1);
                        self
                            .match_predictions_count
                            .write(val.match_id, match_predictions_count + 1);
                        let user_prediction_count = self.user_prediction_count.read(caller);
                        self
                            .user_prediction_index_pointer
                            .write(user_prediction_count + 1, val.match_id);
                        self.user_prediction_count.write(caller, user_prediction_count + 1);
                    },
                    RawPredictionType::Multiple(val) => {
                        assert(!is_single_type, 'INVALID_PARAMS');

                        assert(prediction.pair.is_some(), 'INVALID_PARAMS');
                        // let mut prediction_pair = array![];
                        let mut pair_index = 0;
                        for _val in val {
                            let _match = self.match_details.read(_val.match_id);
                            assert(_match.inputed, Errors::INVALID_MATCH_ID);
                            assert(
                                _match.home.goals.is_none() && _match.away.goals.is_none(),
                                'MATCH_SCORED'
                            );
                            assert(
                                !self.predicted.read((caller, _val.match_id)), Errors::PREDICTED
                            );
                            if let MatchType::Live = _match.match_type {
                                assert(
                                    get_block_timestamp() + 600 < (_match.timestamp),
                                    Errors::PREDICTION_CLOSED
                                );
                            } else {
                                assert(
                                    get_block_timestamp() < (_match.timestamp),
                                    Errors::PREDICTION_CLOSED
                                );
                            }

                            self.predicted.write((caller, _val.match_id), true);
                            let match_predictions_count = self
                                .match_predictions_count
                                .read(_val.match_id);

                            self
                                .prediction_user_id_pointer
                                .write(match_predictions_count + 1, caller);
                            self
                                .prediction_user_index_pointer
                                .write(caller, match_predictions_count + 1);
                            self
                                .match_predictions_count
                                .write(_val.match_id, match_predictions_count + 1);
                            let user_prediction_count = self.user_prediction_count.read(caller);
                            self
                                .user_prediction_index_pointer
                                .write(user_prediction_count + 1, _val.match_id);
                            self.user_prediction_count.write(caller, user_prediction_count + 1);
                            let prediction_construct = Prediction {
                                stake: prediction.stake,
                                inputed: true,
                                prediction_type: PredictionType::Multiple(prediction.pair.unwrap()),
                                odd: Option::Some(self.match_odds.read((_val.match_id, _val.odd)))
                            };
                            self.predictions.write((caller, _val.match_id), prediction_construct);
                            pair_index += 1;
                            self
                                .prediction_pair
                                .write((prediction.pair.unwrap(), pair_index), _val);
                        };
                        self.prediction_pair_count.write(prediction.pair.unwrap(), pair_index);
                    }
                }

                total_stake += prediction.stake;
            };

            if total_stake > 0 {
                let erc20_dispatcher = ERC20ABISafeDispatcher {
                    contract_address: self.erc20_token.read()
                };
                erc20_dispatcher
                    .transfer_from(caller, get_contract_address(), total_stake)
                    .unwrap();
            }
        }


        fn register_matches(ref self: ContractState, matches: Array<RawMatch>) {
            assert(matches.len() > 0, Errors::INVALID_MATCH_LENGTH);
            assert(get_caller_address() == self.owner.read(), Errors::UNAUTHORIZED);

            let total_matches = self.total_matches.read();
            let mut index = total_matches + 1;
            let upcoming_round = self.current_round.read() + 1;
            self
                .round_details
                .write(
                    upcoming_round,
                    RoundDetails {
                        start: index, end: total_matches + matches.len().into(), inputed: true
                    }
                );
            for _match in matches {
                assert(_match.timestamp > 0, Errors::INVALID_TIMESTAMP);
                assert(!self.match_details.read(_match.id).inputed, Errors::MATCH_EXIST);

                for odd in _match
                    .odds {
                        assert(odd.value > 0, 'INVALID_PARAMS');
                        assert(odd.id.is_non_zero(), 'INVALID_PARAMS');
                        assert(odd.tag.is_non_zero(), 'INVALID_PARAMS');
                        self.match_odds.write((_match.id, odd.id), odd);
                    };
                self
                    .match_details
                    .write(
                        _match.id,
                        Match {
                            round: Option::Some(upcoming_round),
                            inputed: true,
                            id: _match.id,
                            timestamp: _match.timestamp,
                            match_type: _match.match_type,
                            home: Team { goals: Option::None, .._match.home },
                            away: Team { goals: Option::None, .._match.away },
                        }
                    );
                self.match_ids.write(index, _match.id);
                self.match_index.write(_match.id, index);
                index += 1;
            };
            self.total_matches.write(index - 1);

            self.current_round.write(upcoming_round);
        }

        fn get_match_odd(self: @ContractState, match_id: felt252, odd_id: felt252) -> u256 {
            self.match_odds.read((match_id, odd_id)).value
        }

        /// test
        fn get_match_by_id(self: @ContractState, id: felt252) -> Match {
            self.match_details.read(id)
        }

        fn get_match_index(self: @ContractState, id: felt252) -> u256 {
            self.match_index.read(id)
        }

        fn set_scores(ref self: ContractState, scores: Array<Score>) {
            assert(get_caller_address() == self.owner.read(), Errors::UNAUTHORIZED);

            for score in scores
                .span() {
                    let _match = self.match_details.read(*score.match_id);

                    assert(_match.inputed, Errors::INVALID_MATCH_ID);
                    if let MatchType::Live = _match.match_type {
                        assert(get_block_timestamp() >= _match.timestamp + 5400, 'MATCH_NOT_ENDED');
                    } else {
                        assert(get_block_timestamp() >= _match.timestamp + 120, 'MATCH_NOT_ENDED');
                    }
                    // assert(_match.winner_odd.is_none(), Errors::SCORED);
                    if _match.home.goals.is_some() {
                        continue;
                    }
                    assert(*score.inputed, 'INVALID_PARAMS');

                    self
                        .match_details
                        .write(
                            *score.match_id,
                            Match {
                                home: Team { goals: Option::Some(*score.home), .._match.home },
                                away: Team { goals: Option::Some(*score.away), .._match.away },
                                .._match
                            }
                        );

                    let match_predictions_count = self
                        .match_predictions_count
                        .read(*score.match_id);

                    let mut index = 1;
                    while index <= match_predictions_count {
                        let user_addr = self.prediction_user_id_pointer.read(index);
                        let prediction = self.predictions.read((user_addr, *score.match_id));

                        match prediction.prediction_type {
                            PredictionType::Single(variants) => {
                                for _win in score
                                    .winner_odds
                                    .span() {
                                        if *_win == variants.odd {
                                            assert(
                                                self
                                                    .match_odds
                                                    .read((*score.match_id, *_win))
                                                    .value > 0,
                                                'INVALID_PARAMS'
                                            );
                                            let winner_odd = prediction.odd.unwrap().value;
                                            self
                                                .user_points
                                                .write(
                                                    user_addr,
                                                    self.user_points.read(user_addr) + winner_odd
                                                );
                                            if prediction.stake > 0 {
                                                self
                                                    .user_rewards
                                                    .write(
                                                        user_addr,
                                                        self.user_rewards.read(user_addr)
                                                            + ((winner_odd * prediction.stake)
                                                                / (100))
                                                    );
                                            }
                                        }
                                        break;
                                    };
                            },
                            PredictionType::Multiple(pair_id) => {
                                let pair_count = self.prediction_pair_count.read(pair_id);
                                let mut _index = 1;
                                let mut match_complete = true;
                                let mut point_accumulation: u256 = 0;
                                let mut false_prediction = false;
                                while _index <= pair_count {
                                    let pair = self.prediction_pair.read((pair_id, _index));
                                    let match_pair = self.match_details.read(pair.match_id);

                                    if match_pair.home.goals.is_none() {
                                        match_complete = false;

                                        break;
                                    }

                                    if let MatchType::Live = match_pair.match_type {
                                        if get_block_timestamp() < match_pair.timestamp + 5400 {
                                            match_complete = false;
                                            break;
                                        }
                                    } else {
                                        if get_block_timestamp() < match_pair.timestamp + 120 {
                                            match_complete = false;
                                            break;
                                        }
                                    }
                                    let mut included = false;

                                    for _score in scores
                                        .span() {
                                            if *_score.match_id == pair.match_id {
                                                for _win in _score
                                                    .winner_odds
                                                    .span() {
                                                        if pair.odd == *_win {
                                                            included = true;
                                                            break;
                                                        }
                                                    }
                                            }
                                        };

                                    if !included {
                                        false_prediction = true;
                                    }

                                    point_accumulation += self
                                        .match_odds
                                        .read((pair.match_id, pair.odd))
                                        .value;

                                    _index += 1;
                                };

                                if match_complete {
                                    self
                                        .user_points
                                        .write(
                                            user_addr,
                                            self.user_points.read(user_addr) + point_accumulation
                                        );

                                    if !false_prediction && prediction.stake > 0 {
                                        self
                                            .user_rewards
                                            .write(
                                                user_addr,
                                                self.user_rewards.read(user_addr)
                                                    + ((point_accumulation * prediction.stake)
                                                        / (100))
                                            );
                                    }
                                }
                            }
                        }

                        index += 1;
                    }
                };
        }


        fn get_user_reward(self: @ContractState, user: ContractAddress) -> u256 {
            self.user_rewards.read(user)
        }

        /// test
        fn get_pair_count(self: @ContractState, pair_id: felt252) -> u256 {
            self.prediction_pair_count.read(pair_id)
        }

        fn claim_reward(ref self: ContractState) {
            let reward = self.user_rewards.read(get_caller_address());
            assert(reward > 0, 'ZERO_BALANCE');
            self.user_rewards.write(get_caller_address(), 0);
            let erc20_dispatcher = ERC20ABISafeDispatcher {
                contract_address: self.erc20_token.read()
            };
            erc20_dispatcher.transfer(get_caller_address(), reward).unwrap();
        }

        fn get_version(self: @ContractState) -> u256 {
            self.version.read()
        }

        fn get_erc20(self: @ContractState) -> ContractAddress {
            self.erc20_token.read()
        }


        fn get_current_round(self: @ContractState) -> u256 {
            self.current_round.read()
        }


        fn get_user_predictions(
            self: @ContractState, user: ContractAddress
        ) -> Array<UserPrediction> {
            assert(user.is_non_zero(), Errors::INVALID_ADDRESS);
            let user_prediction_count = self.user_prediction_count.read(user);
            if user_prediction_count == 0 {
                return array![];
            }

            let mut result = array![];

            let mut index = user_prediction_count;

            while index >= 1 {
                let user_prediction_index_pointer = self.user_prediction_index_pointer.read(index);
                let user_prediction = self.predictions.read((user, user_prediction_index_pointer));
                assert(user_prediction.inputed, 'INVALID_PARAMS');
                let _match = self.match_details.read(user_prediction_index_pointer);
                assert(_match.inputed, 'INVALID_PARAMS');
                let twenty_four_hrs_in_secs = 24 * 60 * 60;
                let is_less_than_24_hrs = if get_block_timestamp() < _match.timestamp {
                    true
                } else {
                    get_block_timestamp() - _match.timestamp < twenty_four_hrs_in_secs
                };
                if is_less_than_24_hrs {
                    let construct = UserPrediction { match_: _match, prediction: user_prediction };
                    result.append(construct);
                };

                index -= 1;
            };

            result
        }


        fn get_user_matches_predictions(
            self: @ContractState, matches: Array<felt252>, user: ContractAddress
        ) -> Array<Prediction> {
            let mut result = array![];

            for match_id in matches {
                let user_prediction = self.predictions.read((user, match_id));
                if user_prediction.inputed {
                    result.append(user_prediction);
                }
            };

            result
        }


        fn get_match_predictions(
            self: @ContractState, match_id: felt252
        ) -> Array<PredictionDetails> {
            let total_players = self.total_users.read();
            let mut index = 1;
            let mut predictions = array![];
            while index <= total_players {
                let user = self.user_by_index.read(index);
                let prediction = self.predictions.read((user.address, match_id));
                if prediction.inputed {
                    predictions.append(PredictionDetails { user, prediction });
                }

                index += 1;
            };

            predictions
        }

        fn get_matches_predictions(
            self: @ContractState, match_ids: Array<felt252>
        ) -> Array<PredictionDetails> {
            let total_players = self.total_users.read();
            let mut index = 1;
            let mut predictions = array![];
            for match_id in match_ids {
                while index <= total_players {
                    let user = self.user_by_index.read(index);
                    let prediction = self.predictions.read((user.address, match_id));
                    if prediction.inputed {
                        predictions.append(PredictionDetails { user, prediction });
                    }

                    index += 1;
                };
            };

            predictions
        }
        fn get_leaderboard(
            self: @ContractState, start_index: u256, size: u256
        ) -> Array<Leaderboard> {
            let total_players = self.total_users.read();

            let mut leaderboard = array![];
            if start_index <= total_players && start_index > 0 {
                let mut count = 0;
                let result_size = if start_index + size > total_players {
                    total_players - (start_index - 1)
                } else {
                    size
                };

                let mut user_index = start_index;
                while count < result_size && user_index <= total_players {
                    let user = self.user_by_index.read(user_index);

                    let leaderboard_construct = Leaderboard {
                        user: self.user.read(user.address),
                        total_score: self.user_points.read(user.address)
                    };
                    leaderboard.append(leaderboard_construct);
                    user_index += 1;
                    count += 1;
                };
            }
            leaderboard
        }


        fn get_user_total_scores(self: @ContractState, address: ContractAddress) -> u256 {
            if (!self.registered.read(address)) {
                return 0;
            }
            self.user_points.read(address)
        }
    }
}
