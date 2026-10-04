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

        // Sync to line: c<a       # now flag is 1
        wait(system_top.cpu.pc == 44 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_flag(1, "c<a       # now flag is 1");

        // Sync to line: c>a       # now flag is 0
        wait(system_top.cpu.pc == 48 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_flag(0, "c>a       # now flag is 0");

        // Sync to line: c=8       # now flag is 1
        wait(system_top.cpu.pc == 52 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_flag(1, "c=8       # now flag is 1");

        // Sync to line: c=f       # now flag is 0
        wait(system_top.cpu.pc == 56 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_flag(0, "c=f       # now flag is 0");

        // Sync to line: r:16        #now r is 16 our radix is now hex.
        wait(system_top.cpu.pc == 61 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("r", 16, "r:16        #now r is 16 our radix is now hex.");

        // Sync to line: b:f         #now b is 15 not 7; a-f source digits, not variables
        wait(system_top.cpu.pc == 65 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("b", 15, "b:f         #now b is 15 not 7; a-f source digits, not variables");

        // Sync to line: r:a         #now r is 10 decimal; 'a' is 10 in hex, and we were in hex
        wait(system_top.cpu.pc == 69 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("r", 10, "r:a         #now r is 10 decimal; 'a' is 10 in hex, and we were in hex");

        // Sync to line: s:0         #now s is 0 Clearing the stack
        wait(system_top.cpu.pc == 73 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("s", 0, "s:0         #now s is 0 Clearing the stack");

        // Sync to line: z,42        #now s is 1 push 42 to stack
        wait(system_top.cpu.pc == 78 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("s", 1, "z,42        #now s is 1 push 42 to stack");

        // Sync to line: # now stack 0 is 42
        wait(system_top.cpu.pc == 78 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_stack(0, 42, "# now stack 0 is 42");

        // Sync to line: ]           # now l is 3 True? PC:TOS : pop TOS
        wait(system_top.cpu.pc == 98 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("l", 3, "]           # now l is 3 True? PC:TOS : pop TOS");

        // Sync to line: # now s is 0 because the stack was emptied
        wait(system_top.cpu.pc == 98 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("s", 0, "# now s is 0 because the stack was emptied");

        // Sync to line: a=5? b:1 ! b:0 .  # now b is 1 because the condition was true
        wait(system_top.cpu.pc == 119 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("b", 1, "a=5? b:1 ! b:0 .  # now b is 1 because the condition was true");

        // Sync to line: .         # now c is 1
        wait(system_top.cpu.pc == 152 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("c", 1, ".         # now c is 1");

        // Sync to line: # now d is 2
        wait(system_top.cpu.pc == 152 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("d", 2, "# now d is 2");

        // Sync to line: a>5? b:1; c:1.  # now b is 0 (Because b was never initialized)
        wait(system_top.cpu.pc == 171 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("b", 0, "a>5? b:1; c:1.  # now b is 0 (Because b was never initialized)");

        // Sync to line: # now c is 1 (True branch skipped, c remains 1)
        wait(system_top.cpu.pc == 171 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("c", 1, "# now c is 1 (True branch skipped, c remains 1)");

        // Sync to line: # now j is 2
        wait(system_top.cpu.pc == 189 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("j", 2, "# now j is 2");

        // Sync to line: x:i@1     # Read array index 1 into x. now x is 2
        wait(system_top.cpu.pc == 202 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("x", 2, "x:i@1     # Read array index 1 into x. now x is 2");

        // Sync to line: y:i@j     # Read array index 2 into y. now y is 42
        wait(system_top.cpu.pc == 208 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("y", 42, "y:i@j     # Read array index 2 into y. now y is 42");

        // Sync to line: a@1:2     # Write 2 to memory address a+1 aka b so now b is 2
        wait(system_top.cpu.pc == 214 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("b", 2, "a@1:2     # Write 2 to memory address a+1 aka b so now b is 2");

        // Sync to line: c:3       # now c is 3
        wait(system_top.cpu.pc == 218 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("c", 3, "c:3       # now c is 3");

        // Sync to line: d:a@b     # Write a@b (aka c) to d so now d is 3
        wait(system_top.cpu.pc == 224 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("d", 3, "d:a@b     # Write a@b (aka c) to d so now d is 3");

