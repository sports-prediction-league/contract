use core::starknet::ContractAddress;


#[derive(Copy, Drop, Debug, Serde, PartialEq, starknet::Store)]
pub struct Score {
    pub inputed: bool,
    pub match_id: felt252,
    pub home: u256,
    pub away: u256,
}


#[derive(Drop, Debug, Serde)]
pub struct Reward {
    pub user: ContractAddress,
    pub reward: u256,
    pub point: u256,
    pub match_id: felt252
}


#[derive(Copy, Drop, Debug, PartialEq, Serde, starknet::Store)]
pub struct Prediction {
    pub inputed: bool,
    pub match_id: felt252,
    pub id: felt252,
    pub stake: u256,
    pub pair: Option<felt252>
}


#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Match {
    pub inputed: bool,
    pub id: felt252,
    pub timestamp: u64,
    pub round: Option<u256>,
    pub match_type: MatchType
}


#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct RoundDetails {
    pub start: u256,
    pub end: u256,
    pub inputed: bool,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Leaderboard {
    pub user: User,
    pub total_score: u256,
}


#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct User {
    pub id: felt252,
    pub username: felt252,
    pub address: ContractAddress,
}

#[derive(Drop, Serde)]
pub struct PredictionDetails {
    pub user: User,
    pub prediction: Prediction,
}


#[derive(Drop, Copy, Clone, Serde, starknet::Store)]
pub enum MatchType {
    #[default]
    Virtual,
    Live,
}
