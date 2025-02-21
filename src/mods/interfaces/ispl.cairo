use starknet::class_hash::ClassHash;
use core::starknet::ContractAddress;

use crate::mods::types::{Score, Reward, PredictionDetails, Leaderboard, Match, User, Prediction};

#[starknet::interface]
pub trait ISPL<TContractState> {
    fn register_user(ref self: TContractState, user: User);
    fn get_user_by_id(self: @TContractState, id: felt252) -> User;
    fn get_user_by_address(self: @TContractState, address: ContractAddress) -> User;
    fn upgrade(ref self: TContractState, impl_hash: ClassHash);
    fn get_version(self: @TContractState) -> u256;
    fn get_leaderboard_by_round(
        self: @TContractState, start_index: u256, size: u256, round: u256
    ) -> Array<Leaderboard>;
    fn get_erc20(self: @TContractState) -> ContractAddress;
    ///test
    fn get_user_by_index(self: @TContractState, index: u256) -> User;
    fn get_match_by_id(self: @TContractState, id: felt252) -> Match;
    fn get_match_index(self: @TContractState, id: felt252) -> u256;
    fn get_leaderboard(self: @TContractState, start_index: u256, size: u256) -> Array<Leaderboard>;
    fn register_matches(ref self: TContractState, matches: Array<Match>);
    fn set_scores(ref self: TContractState, scores: Array<Score>, rewards: Array<Reward>);
    fn get_user_predictions(
        self: @TContractState, round: u256, user: ContractAddress
    ) -> Array<Prediction>;
    fn get_match_scores(self: @TContractState, round: u256) -> Array<Score>;
    fn get_current_round(self: @TContractState) -> u256;
    fn is_address_registered(self: @TContractState, address: ContractAddress) -> bool;
    fn get_user_total_scores(self: @TContractState, address: ContractAddress) -> u256;
    fn get_first_position(self: @TContractState) -> Option<Leaderboard>;
    fn make_bulk_prediction(ref self: TContractState, predictions: Array<Prediction>);
    fn make_prediction(ref self: TContractState, prediction: Prediction);
    fn update_erc20(ref self: TContractState, new_address: ContractAddress);
    fn get_match_predictions(self: @TContractState, match_id: felt252) -> Array<PredictionDetails>;
    fn claim_reward(ref self: TContractState);
    fn get_user_reward(self: @TContractState, user: ContractAddress) -> u256;
}
