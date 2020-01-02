
make
./silo_gen
cp silo_tx ../../verif/sim/test_chronos
cp silo_tx ../../riscv_code/silo/silo_small_ref
(cd ../../riscv_code/silo/; ./silo_sim silo_small_ref silo_small_out > log;)
(cd ../../riscv_code/silo/; cp silo_small_out ../../verif/sim/test_chronos/silo_ref;)

