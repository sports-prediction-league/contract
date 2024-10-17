use starknet::class_hash::ClassHash;
use core::starknet::ContractAddress;


#[starknet::interface]
pub trait IERC20<TContractState> {
    fn get_name(self: @TContractState) -> felt252;
    fn get_symbol(self: @TContractState) -> felt252;
    fn get_decimals(self: @TContractState) -> u8;
    fn get_total_supply(self: @TContractState) -> felt252;
    fn balance_of(self: @TContractState, account: ContractAddress) -> felt252;
    fn allowance(
        self: @TContractState, owner: ContractAddress, spender: ContractAddress
    ) -> felt252;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: felt252);
    fn transfer_from(
        ref self: TContractState,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: felt252
    );
    fn approve(ref self: TContractState, spender: ContractAddress, amount: felt252);
    fn increase_allowance(ref self: TContractState, spender: ContractAddress, added_value: felt252);
    fn decrease_allowance(
        ref self: TContractState, spender: ContractAddress, subtracted_value: felt252
    );
}

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

#[derive(Drop, Serde, starknet::Store)]
 pub struct Leaderboard {
    user:ByteArray,
    total_score:u256,
    
}

#[starknet::interface]
pub trait IPrediction<TContractState> {
    fn increase_balance(ref self: TContractState, amount: felt252);
    fn get_balance(self: @TContractState) -> felt252;
    fn register_user(ref self: TContractState, id: felt252,details:ByteArray);
    fn get_user(self: @TContractState,id:felt252) -> ByteArray;
    fn upgrade(ref self: TContractState, impl_hash: ClassHash);
    fn get_version(self: @TContractState) -> u256;
    fn get_leaderboard(self: @TContractState,start_index:u256, size:u256,round:u256) -> Array<Leaderboard>;
    fn make_prediction(ref self: TContractState, match_id:felt252,home:u256,away:u256);
    fn register_matches(ref self: TContractState, matches:Array<Match>);
    fn set_scores(ref self: TContractState, scores:Array<Score>);
    fn set_erc20(ref self: TContractState, address: ContractAddress);
    fn get_prediction_score(self: @TContractState,round:u256) -> Array<Score>;
    fn get_user_score_per_round(self: @TContractState,round:u256,user_id:felt252) -> u256;
    fn disburse_reward(ref self: TContractState, user: ContractAddress,round:u256,amount:felt252);

}

#[starknet::contract]
mod Prediction {
    use starknet::storage::Map;
    use super::{Errors,Score,Leaderboard,Match,RoundDetails,IERC20Dispatcher,IERC20DispatcherTrait};
    use starknet::{ContractAddress,get_caller_address,get_block_timestamp,get_contract_address};
    use starknet::class_hash::ClassHash;
    use starknet::SyscallResultTrait;
    use core::num::traits::Zero;

    const STAKING_FEE:felt252 = 1_000_000;


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
        balance: felt252, 
        total_users:u256,
        user: Map::<felt252, ByteArray>,
        registered: Map::<felt252, bool>,
        user_id:Map::<u256,felt252>,
        users:Array<felt252>,
        version:u256,
        user_address_pointer:Map::<ContractAddress,felt252>,
        owner:ContractAddress,

        user_claimed_round: Map::<(felt252,u256),bool>,
        total_matches:u256,
        match_details:Map::<felt252,Match>,
        match_index:Map::<felt252,u256>,
        match_ids:Map::<u256,felt252>,
        scores:Map::<felt252,Score>,
        predictions:Map::<(felt252,felt252),Score>,
        current_round:u256,

        total_round_predictions:Map::<u256,u256>,
        round_details:Map::<u256,RoundDetails>,

        erc20_address:ContractAddress
    }



    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner:ContractAddress,
        erc20_address:ContractAddress,
    ) {
        self.owner.write(owner);
        self.erc20_address.write(erc20_address);
      
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
        fn increase_balance(ref self: ContractState, amount: felt252) {
            assert(amount != 0, 'Amount cannot be 0');
            self.balance.write(self.balance.read() + amount);
        }

        fn register_user(ref self: ContractState, id: felt252,details:ByteArray) {
           assert(id != '','INVALID_ID');
           assert(!self.registered.read(id),Errors::ALREADY_EXIST);
           self.registered.write(id,true);
           self.user.write(id,details);
           self.user_id.write(self.total_users.read(),id);
           self.total_users.write(self.total_users.read()+1);
           self.user_address_pointer.write(get_caller_address(),id);
        }

        fn get_user(self: @ContractState,id:felt252) -> ByteArray {
            self.user.read(id)
        }



        fn upgrade(ref self: ContractState, impl_hash: ClassHash) {
            assert(get_caller_address() == self.owner.read(),Errors::UNAUTHORIZED);
            assert(impl_hash.is_non_zero(), Errors::INVAliD_CLASSHASH);
            starknet::syscalls::replace_class_syscall(impl_hash).unwrap_syscall();
            self.version.write(self.version.read()+1);
            self.emit(Event::Upgraded(Upgraded { implementation: impl_hash }));
        }

        fn set_erc20(ref self: ContractState, address: ContractAddress) {
            assert(get_caller_address() == self.owner.read(),Errors::UNAUTHORIZED);
            assert(address.is_non_zero(), Errors::INVALID_ADDRESS);
            self.erc20_address.write(address);
        }


        fn disburse_reward(ref self: ContractState, user: ContractAddress,round:u256,amount:felt252) {
            assert(get_caller_address() == self.owner.read(),Errors::UNAUTHORIZED);
            let user_id = self.user_address_pointer.read(user);
            assert(!self.user_claimed_round.read((user_id,round)),Errors::CLAIMED);
            assert(self.registered.read(user_id),Errors::NOT_REGISTERED);
            assert(round>0, Errors::INVALID_ROUND);
            assert(round<= self.current_round.read(),'OUT_OF_BOUNDS');

            let round_details = self.round_details.read(round);

            assert(round_details.inputed,Errors::INVALID_ROUND);
            assert(round_details.end>0,Errors::INVALID_ROUND);

            let erc20_dispatcher = IERC20Dispatcher{contract_address: self.erc20_address.read()};
            erc20_dispatcher.transfer(user,amount);
            self.user_claimed_round.write((user_id,round),true);
        }


        fn make_prediction(ref self: ContractState, match_id:felt252,home:u256,away:u256) {
            assert(self.registered.read(self.user_address_pointer.read(get_caller_address())),Errors::NOT_REGISTERED);
            let _match = self.match_details.read(match_id);
            assert(_match.inputed,Errors::INVALID_MATCH_ID);
            assert(!self.predictions.read((self.user_address_pointer.read(get_caller_address()),match_id)).inputed,Errors::PREDICTED);
            assert(get_block_timestamp() < (_match.timestamp-600),Errors::PREDICTION_CLOSED);
            let erc20_dispatcher = IERC20Dispatcher{contract_address: self.erc20_address.read()};
            let allowance:u256 = erc20_dispatcher.allowance(get_caller_address(),get_contract_address()).into();
            assert!(allowance>= STAKING_FEE.into(),"NO_ALLOWANCE");
            erc20_dispatcher.transfer_from(get_caller_address(),get_contract_address(),STAKING_FEE);
            self.total_round_predictions.write(_match.round,self.total_round_predictions.read(_match.round)+1);
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
            self.current_round.write(*first_index_round);
            let mut index = self.total_matches.read()+1;
            self.round_details.write(*first_index_round,RoundDetails{start:index,end:self.total_matches.read()+matches.len().into(),inputed:true});
            for _match in matches{
                assert(_match.round == *first_index_round,Errors::MISMATCH_MATCH_ROUND);
                assert(_match.timestamp>0,Errors::INVALID_TIMESTAMP);
                assert(_match.round>0,Errors::INVALID_ROUND);
                assert(!self.match_details.read(_match.id).inputed,Errors::MATCH_EXIST);
                self.match_details.write(_match.id,_match);
                self.match_ids.write(index,_match.id);
                self.match_index.write(_match.id,index);
                index+=1;
            };
        }

        fn set_scores(ref self: ContractState, scores:Array<Score>) {
            assert(get_caller_address() == self.owner.read(),Errors::UNAUTHORIZED);
            for score in scores {
                assert(self.match_details.read(score.match_id).inputed,Errors::INVALID_MATCH_ID);
                assert(!self.scores.read(score.match_id).inputed, Errors::SCORED);
                assert(score.inputed,'INVALID_PARAMS');
                self.scores.write(score.match_id,score);
            }
        }


        fn get_version(self: @ContractState) -> u256 {
            self.version.read()
        }


        fn get_user_score_per_round(self: @ContractState,round:u256,user_id:felt252) -> u256 {
            assert(get_caller_address() == self.owner.read(),Errors::UNAUTHORIZED);
            assert(self.registered.read(user_id),Errors::NOT_REGISTERED);
            assert(round>0, Errors::INVALID_ROUND);
            assert(round<= self.current_round.read(),'OUT_OF_BOUNDS');

            let round_details = self.round_details.read(round);

            assert(round_details.inputed,Errors::INVALID_ROUND);
            assert(round_details.end>0,Errors::INVALID_ROUND);

             calculate_user_scores(self,user_id,round)

            


        }


         fn get_prediction_score(self: @ContractState,round:u256) -> Array<Score> {
            assert(round>0, Errors::INVALID_ROUND);
            assert(round<= self.current_round.read(),'OUT_OF_BOUNDS');
            let mut result = array![];

            let round_details = self.round_details.read(round);

            assert(round_details.inputed,Errors::INVALID_ROUND);
            assert(round_details.end>0,Errors::INVALID_ROUND);

            let mut index = round_details.start;

            while index <= round_details.end {
                let match_id = self.match_ids.read(index);
                let user_prediction = self.predictions.read((self.user_address_pointer.read(get_caller_address()),match_id));
                result.append(user_prediction);
                index+=1;
            };


            result
        }


         fn get_leaderboard(self: @ContractState,start_index:u256, size:u256,round:u256) -> Array<Leaderboard> {
            assert(round>0, Errors::INVALID_ROUND);
            assert(round<= self.current_round.read(),'OUT_OF_BOUNDS');
            let total_players = self.total_users.read();
            assert(start_index<total_players,'OUT_OF_BOUNDS');

            let mut count = 0;
            let result_size = if start_index + size > total_players {
                total_players - start_index
            }else{
                size
            };


            let mut leaderboard = array![];
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

            leaderboard
        }





        fn get_balance(self: @ContractState) -> felt252 {
            self.balance.read()
        }
    }
}
