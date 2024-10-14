use starknet::class_hash::ClassHash;

pub mod Errors {
    pub const INSUFFICIENT_BALANCE: felt252 = 'INSUFFICIENT_BALANCE';
    pub const ALREADY_EXIST: felt252 = 'ALREADY_EXIST';
    pub const INVAliD_CLASSHASH: felt252 = 'INVAliD_CLASSHASH';
    pub const UNAUTHORIZED: felt252 = 'UNAUTHORIZED';
    // you can define more errors here
}

#[starknet::interface]
pub trait IPrediction<TContractState> {
    fn increase_balance(ref self: TContractState, amount: felt252);
    fn get_balance(self: @TContractState) -> felt252;
    fn register_user(ref self: TContractState, id: felt252,details:ByteArray);
    fn get_user(self: @TContractState,id:felt252) -> ByteArray;
    fn upgrade(ref self: TContractState, impl_hash: ClassHash);
    fn get_version(self: @TContractState) -> u256;

}

#[starknet::contract]
mod Prediction {
    use starknet::storage::Map;
    use super::Errors;
    use starknet::{ContractAddress,get_caller_address,get_contract_address};
    use starknet::class_hash::ClassHash;
    use starknet::SyscallResultTrait;
    use core::num::traits::Zero;


    #[storage]
    struct Storage {
        balance: felt252, 
        total_users:u256,
        user: Map::<felt252, ByteArray>,
        registered: Map::<felt252, bool>,
        user_id:Map::<u256,felt252>,
        users:Array<felt252>,
        version:u256,
        owner:ContractAddress
    }


    #[event]
    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub enum Event {
        Upgraded: Upgraded,
    }

    #[derive(Copy, Drop, Debug, PartialEq, starknet::Event)]
    pub struct Upgraded {
        pub implementation: ClassHash
    }

    #[abi(embed_v0)]
    impl PredictionImpl of super::IPrediction<ContractState> {
        fn increase_balance(ref self: ContractState, amount: felt252) {
            assert(amount != 0, 'Amount cannot be 0');
            self.balance.write(self.balance.read() + amount);
        }

        fn register_user(ref self: ContractState, id: felt252,details:ByteArray) {
           assert(!self.registered.read(id),Errors::ALREADY_EXIST);
           self.registered.write(id,true);
           self.user.write(id,details);
           self.user_id.write(self.total_users.read(),id);
           self.total_users.write(self.total_users.read()+1);
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

        fn get_version(self: @ContractState) -> u256 {
            self.version.read()
        }




        fn get_balance(self: @ContractState) -> felt252 {
            self.balance.read()
        }
    }
}
