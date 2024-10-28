use starknet::class_hash::ClassHash;
use core::starknet::ContractAddress;

pub mod Errors {
    pub const INSUFFICIENT_BALANCE: felt252 = 'INSUFFICIENT_BALANCE';
    pub const ALREADY_EXIST: felt252 = 'ALREADY_EXIST';
    pub const INVAliD_CLASSHASH: felt252 = 'INVAliD_CLASSHASH';
    pub const UNAUTHORIZED: felt252 = 'UNAUTHORIZED';
    pub const NOT_REGISTERED: felt252 = 'NOT_REGISTERED';
    pub const INVALID_MATCH_ID: felt252 = 'INVALID_MATCH_ID';
    pub const PREDICTED: felt252 = 'PREDICTED';
    pub const MATCH_EXIST: felt252 = 'MATCH_EXIST';
    pub const SCORED: felt252 = 'SCORED';
    pub const PREDICTION_CLOSED: felt252 = 'PREDICTION_CLOSED';
    pub const INVALID_ADDRESS: felt252 = 'INVALID_ADDRESS';
    pub const INVALID_TIMESTAMP: felt252 = 'INVALID_TIMESTAMP';
    pub const INVALID_ROUND: felt252 = 'INVALID_ROUND';
    pub const MISMATCH_MATCH_ROUND: felt252 = 'MISMATCH_MATCH_ROUND';
    pub const INVALID_MATCH_LENGTH: felt252 = 'INVALID_MATCH_LENGTH';
    pub const CLAIMED: felt252 = 'CLAIMED';
}

#[derive(Copy, Drop, Serde, starknet::Store)]
 pub struct Score {
    inputed:bool,
    match_id:felt252,
    home: u256,
    away: u256,
   
}


#[derive(Copy, Drop, Serde, starknet::Store)]
 pub struct Match {
    inputed:bool,
    id:felt252,
    timestamp: u64,
    round: u256,
}



#[derive(Copy, Drop, Serde, starknet::Store)]
 pub struct RoundDetails {
    start: u256,
    end: u256,
    inputed:bool,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
 pub struct Leaderboard {
    user:felt252,
    total_score:u256,
    
}


#[starknet::interface]
pub trait IPrediction<TContractState> {
    fn register_user(ref self: TContractState, id: felt252,username:felt252);
    fn get_user_by_id(self: @TContractState,id:felt252) -> felt252;
    fn get_user_by_address(self: @TContractState,address:ContractAddress) -> felt252;
    fn upgrade(ref self: TContractState, impl_hash: ClassHash);
    fn get_version(self: @TContractState) -> u256;
    fn get_leaderboard_by_round(self: @TContractState,start_index:u256, size:u256,round:u256) -> Array<Leaderboard>;
    fn get_leaderboard(self: @TContractState,start_index:u256, size:u256) -> Array<Leaderboard>;
    fn make_prediction(ref self: TContractState, match_id:felt252,home:u256,away:u256);
    fn register_matches(ref self: TContractState, matches:Array<Match>);
    fn set_scores(ref self: TContractState, scores:Array<Score>);
    fn get_user_predictions(self: @TContractState,round:u256,user:ContractAddress) -> Array<Score>;
    fn get_match_scores(self: @TContractState,round:u256) -> Array<Score>;
    fn get_current_round(self: @TContractState) -> u256;
    fn is_address_registered(self: @TContractState,address:ContractAddress) -> bool;
    fn get_user_total_scores(self: @TContractState,user_id:felt252) -> u256;
    fn get_first_position(self: @TContractState) -> Option<Leaderboard>;

}

#[starknet::contract]
mod Prediction {
    use starknet::storage::Map;
    use super::{Errors,Score,Leaderboard,Match,RoundDetails};
    use starknet::{ContractAddress,get_caller_address,get_block_timestamp};
    use starknet::class_hash::ClassHash;
    use starknet::SyscallResultTrait;
    use core::num::traits::Zero;

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
        total_users:u256,
        user: Map::<felt252, felt252>,
        registered: Map::<felt252, bool>,
        user_id:Map::<u256,felt252>,
        users:Array<felt252>,
        version:u256,
        user_address_pointer:Map::<ContractAddress,felt252>,
        owner:ContractAddress,
        total_matches:u256,
        match_details:Map::<felt252,Match>,
        match_index:Map::<felt252,u256>,
        match_ids:Map::<u256,felt252>,
        scores:Map::<felt252,Score>,
        predictions:Map::<(felt252,felt252),Score>,
        current_round:u256,
        round_details:Map::<u256,RoundDetails>,
    }



    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner:ContractAddress,
    ) {
        self.owner.write(owner);
    }

  
    fn get_goal_range(home:u256,away:u256) -> felt252 {
        let total_goals = home+away;
        if total_goals<=2{
            return '0-2';
        }else{
            return '3+';
        }
    }

    fn calculate_user_scores(self: @ContractState,user_id:felt252,round:u256) -> u256{
        let mut user_total_score:u256 = 0;
        let round_details = self.round_details.read(round);

        assert(round_details.inputed,Errors::INVALID_ROUND);
        assert(round_details.end>0,Errors::INVALID_ROUND);

        let mut index = round_details.start;

        while index <= round_details.end {
            let match_id = self.match_ids.read(index);
            let match_score = self.scores.read(match_id);
            let user_match_prediction = self.predictions.read((user_id,match_id));

            if match_score.inputed {
                if user_match_prediction.inputed {
                    let actual_goal_range = get_goal_range(match_score.home,match_score.away);
                    let predicted_goal_range = get_goal_range(user_match_prediction.home,user_match_prediction.away);

                    let actual_result = if match_score.home ==   match_score.away {
                        'draw'
                    }else{
                        if match_score.home > match_score.away {
                            'home'
                        }else{
                            'away'
                        }
                    };


                    let predicted_result = if user_match_prediction.home == user_match_prediction.away {
                        'draw'
                    }else{
                        if user_match_prediction.home> user_match_prediction.away {
                            'home'
                        }else{
                            'away'
                        }
                    };


                    if match_score.home == user_match_prediction.home &&match_score.away == user_match_prediction.away && actual_goal_range == predicted_goal_range {
                        user_total_score+=5;
                    }else if predicted_result == actual_result && actual_goal_range == predicted_goal_range {
                        user_total_score+=3;
                    }else if predicted_result == actual_result {
                        user_total_score+=2;
                    }
                
                }
            }
            index+=1;

        };

        user_total_score
    }

    #[abi(embed_v0)]
    impl PredictionImpl of super::IPrediction<ContractState> {


        fn register_user(ref self: ContractState, id: felt252,username:felt252) {
           assert(id != '','INVALID_ID');
           assert(username != '' &&username !=0,'INVALID_ID');
           assert(!self.registered.read(id)&& !self.registered.read(username),Errors::ALREADY_EXIST);
           self.registered.write(id,true);
           self.registered.write(username,true);
           self.user.write(id,username);
           self.user_id.write(self.total_users.read(),id);
           self.total_users.write(self.total_users.read()+1);
           self.user_address_pointer.write(get_caller_address(),id);
        }



        fn get_user_by_id(self: @ContractState,id:felt252) -> felt252 {
            self.user.read(id)
        }


        fn is_address_registered(self: @ContractState,address:ContractAddress) -> bool {
            self.registered.read(self.user_address_pointer.read(address))
        }

        fn get_user_by_address(self: @ContractState,address:ContractAddress) -> felt252 {
            self.user.read(self.user_address_pointer.read(address))
        }



        fn upgrade(ref self: ContractState, impl_hash: ClassHash) {
            assert(get_caller_address() == self.owner.read(),Errors::UNAUTHORIZED);
            assert(impl_hash.is_non_zero(), Errors::INVAliD_CLASSHASH);
            starknet::syscalls::replace_class_syscall(impl_hash).unwrap_syscall();
            self.version.write(self.version.read()+1);
            self.emit(Event::Upgraded(Upgraded { implementation: impl_hash }));
        }


        fn make_prediction(ref self: ContractState, match_id:felt252,home:u256,away:u256) {
            assert(self.registered.read(self.user_address_pointer.read(get_caller_address())),Errors::NOT_REGISTERED);
            let _match = self.match_details.read(match_id);
            assert(_match.inputed,Errors::INVALID_MATCH_ID);
            assert(!self.scores.read(_match.id).inputed,'MATCH_SCORED');
            assert(!self.predictions.read((self.user_address_pointer.read(get_caller_address()),match_id)).inputed,Errors::PREDICTED);
            assert(get_block_timestamp()+600 < (_match.timestamp),Errors::PREDICTION_CLOSED);
            let score_construct = Score {
                inputed:true,
                match_id,
                home,
                away
            };
            self.predictions.write((self.user_address_pointer.read(get_caller_address()),match_id),score_construct);           
        }


        fn register_matches(ref self: ContractState, matches:Array<Match>) {
            assert(matches.len()>0,Errors::INVALID_MATCH_LENGTH);
            assert(get_caller_address() == self.owner.read(),Errors::UNAUTHORIZED);
            let first_index_round = matches[0].round;
            assert(*first_index_round>0,'INVALID_PARAMS');
            self.total_matches.write(self.total_matches.read()+matches.len().into());
            let mut index = self.total_matches.read()+1;
            let upcoming_round = self.current_round.read()+1;
            self.round_details.write(upcoming_round,RoundDetails{start:index,end:self.total_matches.read()+matches.len().into(),inputed:true});
            for _match in matches{
                assert(_match.round == *first_index_round,Errors::MISMATCH_MATCH_ROUND);
                assert(_match.timestamp>0,Errors::INVALID_TIMESTAMP);
                assert(_match.round>0,Errors::INVALID_ROUND);
                assert(!self.match_details.read(_match.id).inputed,Errors::MATCH_EXIST);
                self.match_details.write(_match.id,Match{round: upcoming_round,inputed:true,.._match});
                self.match_ids.write(index,_match.id);
                self.match_index.write(_match.id,index);
                index+=1;
            };

            self.current_round.write(upcoming_round);
        }

        fn set_scores(ref self: ContractState, scores:Array<Score>) {
            assert(get_caller_address() == self.owner.read(),Errors::UNAUTHORIZED);
            for score in scores {
                let _match = self.match_details.read(score.match_id);
                assert(get_block_timestamp()>= _match.timestamp+5400,'MATCH_NOT_ENDED');
                assert(_match.inputed,Errors::INVALID_MATCH_ID);
                assert(!self.scores.read(score.match_id).inputed, Errors::SCORED);
                assert(score.inputed,'INVALID_PARAMS');
                self.scores.write(score.match_id,score);
            }
        }


        fn get_version(self: @ContractState) -> u256 {
            self.version.read()
        }

        fn get_current_round(self: @ContractState) -> u256 {
            self.current_round.read()
        }



        fn get_user_predictions(self: @ContractState,round:u256,user:ContractAddress) -> Array<Score> {
            assert(round>0, Errors::INVALID_ROUND);
            assert(round<= self.current_round.read(),'OUT_OF_BOUNDS');
            let mut result = array![];

            let round_details = self.round_details.read(round);

            assert(round_details.inputed,Errors::INVALID_ROUND);
            assert(round_details.end>0,Errors::INVALID_ROUND);

            let mut index = round_details.start;

            while index <= round_details.end {
                let match_id = self.match_ids.read(index);
                let user_prediction = self.predictions.read((self.user_address_pointer.read(user),match_id));
                result.append(user_prediction);
                index+=1;
            };


            result
        }

        fn get_match_scores(self: @ContractState,round:u256) -> Array<Score> {
            assert(round>0, Errors::INVALID_ROUND);
            assert(round<= self.current_round.read(),'OUT_OF_BOUNDS');
            let mut result = array![];

            let round_details = self.round_details.read(round);

            assert(round_details.inputed,Errors::INVALID_ROUND);
            assert(round_details.end>0,Errors::INVALID_ROUND);

            let mut index = round_details.start;

            while index <= round_details.end {
                let match_id = self.match_ids.read(index);
                let score = self.scores.read(match_id);
                result.append(score);
                index+=1;
            };


            result
        }


        fn get_leaderboard_by_round(self: @ContractState,start_index:u256, size:u256,round:u256) -> Array<Leaderboard> {
            assert(round>0, Errors::INVALID_ROUND);
            assert(round<= self.current_round.read(),'OUT_OF_BOUNDS');
            let total_players = self.total_users.read();

            let mut leaderboard = array![];
            if start_index < total_players {

                let mut count = 0;
                let result_size = if start_index + size > total_players {
                    total_players - start_index
                }else{
                    size
                };


                let mut index = start_index;
                while count < result_size && index < total_players {
                    let user_id = self.user_id.read(index);
                    let user_total_score = calculate_user_scores(self,user_id,round);
                    let leaderboard_construct = Leaderboard{
                        user:self.user.read(user_id),
                        total_score:user_total_score
                    };
                    leaderboard.append(leaderboard_construct);
                    index+=1;
                    count+=1;
                };

            }
            leaderboard
        }




        fn get_leaderboard(self: @ContractState,start_index:u256, size:u256) -> Array<Leaderboard> {
          
            let total_players = self.total_users.read();

            let mut leaderboard = array![];
            if start_index < total_players {

                let mut count = 0;
                let result_size = if start_index + size > total_players {
                    total_players - start_index
                }else{
                    size
                };


                let mut user_index = start_index;
                while count < result_size && user_index < total_players {
                    let user_id = self.user_id.read(user_index);
                    let mut user_total_score = 0;
                    let mut round_index = self.current_round.read();
                    while round_index > 0 {
                        let user_round_total_score = calculate_user_scores(self,user_id,round_index);
                        user_total_score+=user_round_total_score;
                        round_index-=1;
                    };
                    let leaderboard_construct = Leaderboard{
                        user:self.user.read(user_id),
                        total_score:user_total_score
                    };
                    leaderboard.append(leaderboard_construct);
                    user_index+=1;
                    count+=1;
                };

            }
            leaderboard
        }



        fn get_user_total_scores(self: @ContractState,user_id:felt252) -> u256 {
          
            if(!self.registered.read(user_id)){
                return 0;
            }
            let mut user_total_score = 0;
            let mut round_index = self.current_round.read();
            while round_index > 0 {
                let user_round_total_score = calculate_user_scores(self,user_id,round_index);
                user_total_score+=user_round_total_score;
                round_index-=1;
            };
                  
             
            user_total_score
        }

        fn get_first_position(self: @ContractState) -> Option<Leaderboard> {
          
            let total_players = self.total_users.read();

            let mut leaderboard:Option<Leaderboard> = Option::None;




            let mut user_index = 0;
            while user_index < total_players {
                let user_id = self.user_id.read(user_index);
                let mut user_total_score = 0;
                let mut round_index = self.current_round.read();
                while round_index > 0 {
                    let user_round_total_score = calculate_user_scores(self,user_id,round_index);
                    user_total_score+=user_round_total_score;
                    round_index-=1;
                };
                if let Option::Some(_current) = leaderboard {
                    if user_total_score> _current.total_score{
                        let leaderboard_construct = Leaderboard{
                            user:self.user.read(user_id),
                            total_score:user_total_score
                        };
                        leaderboard = Option::Some(leaderboard_construct);
                    }

                }else{

                    let leaderboard_construct = Leaderboard{
                        user:self.user.read(user_id),
                        total_score:user_total_score
                    };

                    leaderboard = Option::Some(leaderboard_construct);
                }
                user_index+=1;
            };

            leaderboard
        }     
    }
}
