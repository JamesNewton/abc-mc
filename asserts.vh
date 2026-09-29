        // Sync to line: f:7         # now f is 7
        wait(system_top.cpu.pc == 4 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("f", 7, "f:7         # now f is 7");

        // Sync to line: f:f+3       # now f is 10
        wait(system_top.cpu.pc == 10 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("f", 10, "f:f+3       # now f is 10");

        // Sync to line: f:f-3       # now f is 7
        wait(system_top.cpu.pc == 16 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("f", 7, "f:f-3       # now f is 7");

        // Sync to line: f:f&4|1^2   # now f is 7
        wait(system_top.cpu.pc == 26 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("f", 7, "f:f&4|1^2   # now f is 7");

        // Sync to line: a:f*6       #now a is 42 Multiplication
        wait(system_top.cpu.pc == 32 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("a", 42, "a:f*6       #now a is 42 Multiplication");

        // Sync to line: c:a/6+1     #now c is 8 Division (integer)
        wait(system_top.cpu.pc == 40 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("c", 8, "c:a/6+1     #now c is 8 Division (integer)");

        // Sync to line: r:16        #now r is 16 our radix is now hex.
        wait(system_top.cpu.pc == 45 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("r", 16, "r:16        #now r is 16 our radix is now hex.");

        // Sync to line: b:f         #now b is 15 not 7; a-f source digits, not variables
        wait(system_top.cpu.pc == 49 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("b", 15, "b:f         #now b is 15 not 7; a-f source digits, not variables");

        // Sync to line: r:a         #now r is 10 decimal; 'a' is 10 in hex, and we were in hex
        wait(system_top.cpu.pc == 53 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("r", 10, "r:a         #now r is 10 decimal; 'a' is 10 in hex, and we were in hex");

        // Sync to line: s:0         #now s is 0 Clearing the stack
        wait(system_top.cpu.pc == 57 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("s", 0, "s:0         #now s is 0 Clearing the stack");

        // Sync to line: z,42        #now s is 1 push 42 to stack
        wait(system_top.cpu.pc == 62 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("s", 1, "z,42        #now s is 1 push 42 to stack");

        // Sync to line: # now stack 0 is 42
        wait(system_top.cpu.pc == 62 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_stack(0, 42, "# now stack 0 is 42");

