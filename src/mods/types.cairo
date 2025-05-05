use core::starknet::ContractAddress;

#[derive(Drop, Serde,)]
pub struct Score {
    pub inputed: bool,
    pub home: u8,
    pub away: u8,
    pub match_id: felt252,
    pub winner_odds: Array<felt252>,
}


#[derive(Drop, Debug, Serde)]
pub struct Reward {
    pub user: ContractAddress,
    pub reward: u256,
    pub point: u256,
    pub match_id: felt252
}


#[derive(Serde, Drop)]
pub struct RawPrediction {
    pub stake: u256,
    pub prediction_type: RawPredictionType,
    pub pair: Option<felt252>
}


#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Prediction {
    pub inputed: bool,
    // pub match_id: felt252,
    // pub odd_id: felt252,
    pub odd: Option<Odd>,
    pub stake: u256,
    pub prediction_type: PredictionType,
    // pub pair: Option<felt252>
}

#[derive(Copy, Drop, Serde)]
pub struct UserPrediction {
    pub match_: Match,
    // pub prediction_tag: felt252,
    pub prediction: Prediction
}


#[derive(Copy, Drop, Debug, Serde, starknet::Store)]
pub struct Match {
    pub inputed: bool,
    pub id: felt252,
    pub timestamp: u64,
    pub home: Team,
    pub away: Team,
    pub round: Option<u256>,
    pub match_type: MatchType,
    // pub winner_odd: Option<felt252>
}

#[derive(Copy, Drop, Debug, Serde, starknet::Store)]
pub struct Team {
    pub id: felt252,
    pub goals: Option<u8>,
}


#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct Odd {
    pub id: felt252,
    pub value: u256,
    pub tag: felt252,
}
#[derive(Drop, Serde)]
pub struct RawMatch {
    pub id: felt252,
    pub timestamp: u64,
    pub round: Option<u256>,
    pub match_type: MatchType,
    pub odds: Array<Odd>,
    pub home: Team,
    pub away: Team,
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


#[derive(Drop, Copy, Clone, Debug, Serde, starknet::Store)]
pub enum MatchType {
    #[default]
    Virtual,
    Live,
}

#[derive(Drop, Copy, Debug, PartialEq, Serde, starknet::Store)]
pub struct PredictionVariants {
    pub match_id: felt252,
    pub odd: felt252
}
#[derive(Drop, Copy, Debug, PartialEq, Serde, starknet::Store)]
pub enum PredictionType {
    #[default]
    Single: PredictionVariants,
    Multiple: MultiplePredictionVariants,
}

#[derive(Drop, Copy, Debug, PartialEq, Serde, starknet::Store)]
pub struct MultiplePredictionVariants {
    pub match_id: felt252,
    pub pair_id: felt252,
    pub odd: felt252
}

#[derive(Serde, Drop, PartialEq)]
pub enum RawPredictionType {
    #[default]
    Single: PredictionVariants,
    Multiple: Array<PredictionVariants>
}
