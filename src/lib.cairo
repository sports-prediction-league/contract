pub mod mods;

#[starknet::contract]
pub mod SPL {
    use openzeppelin_token::erc20::interface::ERC20ABISafeDispatcherTrait;
    use starknet::storage::Map;
    use super::mods::{
        types::{
            Score, Reward, PredictionDetails, Leaderboard, Match, RoundDetails, MatchType, User,
            Prediction
        },
        constants::Errors, interfaces::ispl::ISPL
    };
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_contract_address};
    use starknet::class_hash::ClassHash;
    use starknet::SyscallResultTrait;
    use core::num::traits::Zero;

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
        match_index: Map::<felt252, u256>,
        match_ids: Map::<u256, felt252>,
        match_scores: Map::<felt252, Score>,
        users_scores: Map::<(ContractAddress, felt252), u256>,
        predictions: Map::<(ContractAddress, felt252), Prediction>,
        match_pool: Map::<felt252, u256>,
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


    fn calculate_user_scores(
        self: @ContractState, user_address: ContractAddress, round: u256
    ) -> u256 {
        let mut user_total_score: u256 = 0;
        let round_details = self.round_details.read(round);

        assert(round_details.inputed, Errors::INVALID_ROUND);
        assert(round_details.end > 0, Errors::INVALID_ROUND);

        let mut index = round_details.start;

        while index <= round_details.end {
            let match_id = self.match_ids.read(index);
            let match_score = self.match_scores.read(match_id);
            let user_match_prediction = self.predictions.read((user_address, match_id));

            if match_score.inputed {
                if user_match_prediction.inputed {
                    let point = self.users_scores.read((user_address, match_id));
                    user_total_score += point;
                }
            }
            index += 1;
        };

        user_total_score
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


        fn make_prediction(ref self: ContractState, prediction: Prediction) {
            let caller = get_caller_address();
            assert(self.registered.read(caller), Errors::NOT_REGISTERED);
            let match_id = prediction.match_id;
            let _match = self.match_details.read(match_id);
            assert(_match.inputed, Errors::INVALID_MATCH_ID);
            assert(!self.match_scores.read(_match.id).inputed, 'MATCH_SCORED');
            assert(!self.predictions.read((caller, match_id)).inputed, Errors::PREDICTED);
            if let MatchType::Live = _match.match_type {
                assert(get_block_timestamp() + 600 < (_match.timestamp), Errors::PREDICTION_CLOSED);
            } else {
                assert(get_block_timestamp() < (_match.timestamp), Errors::PREDICTION_CLOSED);
            }
            if prediction.stake > 0 {
                let erc20_dispatcher = ERC20ABISafeDispatcher {
                    contract_address: self.erc20_token.read()
                };

                erc20_dispatcher
                    .transfer_from(caller, get_contract_address(), prediction.stake)
                    .unwrap();
            }
            self.predictions.write((caller, match_id), Prediction { inputed: true, ..prediction });
        }

        fn make_bulk_prediction(ref self: ContractState, predictions: Array<Prediction>) {
            let caller = get_caller_address();
            assert(self.registered.read(caller), Errors::NOT_REGISTERED);
            let mut total_stakes: u256 = 0;

            for prediction in predictions {
                let match_id = prediction.match_id;
                let _match = self.match_details.read(match_id);
                assert(_match.inputed, Errors::INVALID_MATCH_ID);
                assert(!self.match_scores.read(_match.id).inputed, 'MATCH_SCORED');
                assert(!self.predictions.read((caller, match_id)).inputed, Errors::PREDICTED);
                if let MatchType::Live = _match.match_type {
                    assert(
                        get_block_timestamp() + 600 < (_match.timestamp), Errors::PREDICTION_CLOSED
                    );
                } else {
                    assert(get_block_timestamp() < (_match.timestamp), Errors::PREDICTION_CLOSED);
                }

                self
                    .predictions
                    .write((caller, match_id), Prediction { inputed: true, ..prediction });
                total_stakes += prediction.stake;
            };

            if total_stakes > 0 {
                let erc20_dispatcher = ERC20ABISafeDispatcher {
                    contract_address: self.erc20_token.read()
                };
                erc20_dispatcher
                    .transfer_from(caller, get_contract_address(), total_stakes)
                    .unwrap();
            }
        }


        fn register_matches(ref self: ContractState, matches: Array<Match>) {
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
                self
                    .match_details
                    .write(
                        _match.id,
                        Match { round: Option::Some(upcoming_round), inputed: true, .._match }
                    );
                self.match_ids.write(index, _match.id);
                self.match_index.write(_match.id, index);
                index += 1;
            };
            self.total_matches.write(index - 1);

            self.current_round.write(upcoming_round);
        }

        /// test
        fn get_match_by_id(self: @ContractState, id: felt252) -> Match {
            self.match_details.read(id)
        }

        fn get_match_index(self: @ContractState, id: felt252) -> u256 {
            self.match_index.read(id)
        }

        fn set_scores(ref self: ContractState, scores: Array<Score>, rewards: Array<Reward>) {
            assert(get_caller_address() == self.owner.read(), Errors::UNAUTHORIZED);
            for score in scores {
                let _match = self.match_details.read(score.match_id);
                if let MatchType::Live = _match.match_type {
                    assert(get_block_timestamp() >= _match.timestamp + 5400, 'MATCH_NOT_ENDED');
                } else {
                    assert(get_block_timestamp() >= _match.timestamp + 120, 'MATCH_NOT_ENDED');
                }
                assert(_match.inputed, Errors::INVALID_MATCH_ID);
                assert(!self.match_scores.read(score.match_id).inputed, Errors::SCORED);
                assert(score.inputed, 'INVALID_PARAMS');
                self.match_scores.write(score.match_id, score);
            };

            for reward in rewards {
                if reward.reward < 1 {
                    continue;
                }
                assert(
                    self.predictions.read((reward.user, reward.match_id)).inputed,
                    'USER_NOT_PREDICTED'
                );

                self.users_scores.write((reward.user, reward.match_id), reward.point);

                self
                    .user_rewards
                    .write(reward.user, self.user_rewards.read(reward.user) + reward.reward);
            }
        }


        fn get_user_reward(self: @ContractState, user: ContractAddress) -> u256 {
            self.user_rewards.read(user)
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
            self: @ContractState, round: u256, user: ContractAddress
        ) -> Array<Prediction> {
            assert(round > 0, Errors::INVALID_ROUND);
            assert(round <= self.current_round.read(), 'OUT_OF_BOUNDS');
            let mut result = array![];

            let round_details = self.round_details.read(round);

            assert(round_details.inputed, Errors::INVALID_ROUND);
            assert(round_details.end > 0, Errors::INVALID_ROUND);

            let mut index = round_details.start;

            while index <= round_details.end {
                let match_id = self.match_ids.read(index);
                let user_prediction = self.predictions.read((user, match_id));
                if user_prediction.inputed {
                    result.append(user_prediction);
                }
                index += 1;
            };

            result
        }

        fn get_match_scores(self: @ContractState, round: u256) -> Array<Score> {
            assert(round > 0, Errors::INVALID_ROUND);
            assert(round <= self.current_round.read(), 'OUT_OF_BOUNDS');
            let mut result = array![];

            let round_details = self.round_details.read(round);

            assert(round_details.inputed, Errors::INVALID_ROUND);
            assert(round_details.end > 0, Errors::INVALID_ROUND);

            let mut index = round_details.start;

            while index <= round_details.end {
                let match_id = self.match_ids.read(index);
                let score = self.match_scores.read(match_id);
                result.append(score);
                index += 1;
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


        fn get_leaderboard_by_round(
            self: @ContractState, start_index: u256, size: u256, round: u256
        ) -> Array<Leaderboard> {
            assert(round > 0, Errors::INVALID_ROUND);
            assert(round <= self.current_round.read(), 'OUT_OF_BOUNDS');
            let total_players = self.total_users.read();

            let mut leaderboard = array![];
            if start_index <= total_players && start_index > 0 {
                let mut count = 0;
                let result_size = if start_index + size > total_players {
                    total_players - start_index - 1
                } else {
                    size
                };

                let mut index = start_index;
                while count < result_size && index <= total_players {
                    let user = self.user_by_index.read(index);
                    let user_total_score = calculate_user_scores(self, user.address, round);
                    let leaderboard_construct = Leaderboard {
                        user: self.user.read(user.address), total_score: user_total_score
                    };
                    leaderboard.append(leaderboard_construct);
                    index += 1;
                    count += 1;
                };
            }
            leaderboard
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
                    let mut user_total_score = 0;
                    let mut round_index = self.current_round.read();
                    while round_index > 0 {
                        let user_round_total_score = calculate_user_scores(
                            self, user.address, round_index
                        );
                        user_total_score += user_round_total_score;
                        round_index -= 1;
                    };
                    let leaderboard_construct = Leaderboard {
                        user: self.user.read(user.address), total_score: user_total_score
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
            let mut user_total_score = 0;
            let mut round_index = self.current_round.read();
            while round_index > 0 {
                let user_round_total_score = calculate_user_scores(self, address, round_index);
                user_total_score += user_round_total_score;
                round_index -= 1;
            };

            user_total_score
        }

        fn get_first_position(self: @ContractState) -> Option<Leaderboard> {
            let total_players = self.total_users.read();

            let mut leaderboard: Option<Leaderboard> = Option::None;

            let mut user_index = 0;
            while user_index <= total_players {
                let user = self.user_by_index.read(user_index);
                let mut user_total_score = 0;
                let mut round_index = self.current_round.read();
                while round_index > 0 {
                    let user_round_total_score = calculate_user_scores(
                        self, user.address, round_index
                    );
                    user_total_score += user_round_total_score;
                    round_index -= 1;
                };
                if let Option::Some(_current) = leaderboard {
                    if user_total_score > _current.total_score {
                        let leaderboard_construct = Leaderboard {
                            user: self.user.read(user.address), total_score: user_total_score
                        };
                        leaderboard = Option::Some(leaderboard_construct);
                    }
                } else {
                    let leaderboard_construct = Leaderboard {
                        user: self.user.read(user.address), total_score: user_total_score
                    };

                    leaderboard = Option::Some(leaderboard_construct);
                }
                user_index += 1;
            };

            leaderboard
        }
    }
}
