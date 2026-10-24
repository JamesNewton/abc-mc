        // Sync to line: a=0       # now flag is 1 (Proves function string wasn't executed)
        wait(system_top.cpu.pc >= 19 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_flag(1, "a=0       # now flag is 1 (Proves function string wasn't executed)");

        // Sync to line: f()       # now a is 1
        wait(system_top.cpu.pc >= 23 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("a", 1, "f()       # now a is 1");

        // Sync to line: # now s is 0
        wait(system_top.cpu.pc >= 23 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("s", 0, "# now s is 0");

        // Sync to line: b:f(2)    # now b is 1 the return value from the function.
        wait(system_top.cpu.pc >= 30 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("b", 1, "b:f(2)    # now b is 1 the return value from the function.");

        // Sync to line: c:g(5)      #now c is 16
        wait(system_top.cpu.pc >= 50 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("c", 16, "c:g(5)      #now c is 16");

        // Sync to line: f:7         # now f is 7
        wait(system_top.cpu.pc >= 54 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("f", 7, "f:7         # now f is 7");

        // Sync to line: f:f+3       # now f is 10
        wait(system_top.cpu.pc >= 60 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("f", 10, "f:f+3       # now f is 10");

        // Sync to line: f:f-3       # now f is 7
        wait(system_top.cpu.pc >= 66 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("f", 7, "f:f-3       # now f is 7");

        // Sync to line: f:f&4|1^2   # now f is 7
        wait(system_top.cpu.pc >= 76 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("f", 7, "f:f&4|1^2   # now f is 7");

        // Sync to line: a:f*6       #now a is 42 Multiplication
        wait(system_top.cpu.pc >= 82 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("a", 42, "a:f*6       #now a is 42 Multiplication");

        // Sync to line: c:a/6+1     #now c is 8 Division (integer)
        wait(system_top.cpu.pc >= 90 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("c", 8, "c:a/6+1     #now c is 8 Division (integer)");

        // Sync to line: c<a       # now flag is 1
        wait(system_top.cpu.pc >= 94 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_flag(1, "c<a       # now flag is 1");

        // Sync to line: c>a       # now flag is 0
        wait(system_top.cpu.pc >= 98 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_flag(0, "c>a       # now flag is 0");

        // Sync to line: c=8       # now flag is 1
        wait(system_top.cpu.pc >= 102 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_flag(1, "c=8       # now flag is 1");

        // Sync to line: c=f       # now flag is 0
        wait(system_top.cpu.pc >= 106 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_flag(0, "c=f       # now flag is 0");

        // Sync to line: r:16        #now r is 16 our radix is now hex.
        wait(system_top.cpu.pc >= 111 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("r", 16, "r:16        #now r is 16 our radix is now hex.");

        // Sync to line: b:f         #now b is 15 not 7; a-f source digits, not variables
        wait(system_top.cpu.pc >= 115 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("b", 15, "b:f         #now b is 15 not 7; a-f source digits, not variables");

        // Sync to line: r:a         #now r is 10 decimal; 'a' is 10 in hex, and we were in hex
        wait(system_top.cpu.pc >= 119 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("r", 10, "r:a         #now r is 10 decimal; 'a' is 10 in hex, and we were in hex");

        // Sync to line: ]           # now l is 3 True? PC:TOS : pop TOS
        wait(system_top.cpu.pc >= 139 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("l", 3, "]           # now l is 3 True? PC:TOS : pop TOS");

        // Sync to line: # now s is 0 because the stack was emptied
        wait(system_top.cpu.pc >= 139 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("s", 0, "# now s is 0 because the stack was emptied");

        // Sync to line: a=5? b:1 ! b:0 .  # now b is 1 because the condition was true
        wait(system_top.cpu.pc >= 160 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("b", 1, "a=5? b:1 ! b:0 .  # now b is 1 because the condition was true");

        // Sync to line: .         # now c is 1
        wait(system_top.cpu.pc >= 193 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("c", 1, ".         # now c is 1");

        // Sync to line: # now d is 2
        wait(system_top.cpu.pc >= 193 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("d", 2, "# now d is 2");

        // Sync to line: a>5? b:1; c:1.  # now b is 0 (Because b was never initialized)
        wait(system_top.cpu.pc >= 212 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("b", 0, "a>5? b:1; c:1.  # now b is 0 (Because b was never initialized)");

        // Sync to line: # now c is 1 (True branch skipped, c remains 1)
        wait(system_top.cpu.pc >= 212 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("c", 1, "# now c is 1 (True branch skipped, c remains 1)");

        // Sync to line: j:j # now j is 15
        wait(system_top.cpu.pc >= 303 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("j", 15, "j:j # now j is 15");

        // Sync to line: # now j is 2
        wait(system_top.cpu.pc >= 321 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("j", 2, "# now j is 2");

        // Sync to line: x:i@1     # Read array index 1 into x. now x is 2
        wait(system_top.cpu.pc >= 334 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("x", 2, "x:i@1     # Read array index 1 into x. now x is 2");

        // Sync to line: y:i@j     # Read array index 2 into y. now y is 42
        wait(system_top.cpu.pc >= 340 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("y", 42, "y:i@j     # Read array index 2 into y. now y is 42");

        // Sync to line: a@1:2     # Write 2 to memory address a+1 aka b so now b is 2
        wait(system_top.cpu.pc >= 346 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("b", 2, "a@1:2     # Write 2 to memory address a+1 aka b so now b is 2");

        // Sync to line: c:3       # now c is 3
        wait(system_top.cpu.pc >= 350 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("c", 3, "c:3       # now c is 3");

        // Sync to line: d:a@b     # Write a@b (aka c) to d so now d is 3
        wait(system_top.cpu.pc >= 356 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("d", 3, "d:a@b     # Write a@b (aka c) to d so now d is 3");

        // Sync to line: s:0         #now s is 0 Clearing the stack
        wait(system_top.cpu.pc >= 360 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("s", 0, "s:0         #now s is 0 Clearing the stack");

        // Sync to line: z,42        #now s is 1 push 42 to stack
        wait(system_top.cpu.pc >= 365 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_register("s", 1, "z,42        #now s is 1 push 42 to stack");

        // Sync to line: # now stack 0 is 42
        wait(system_top.cpu.pc >= 365 && system_top.cpu.fsm_state == 0);
        @(posedge clk); // Give memory 1 tick to save
        assert_stack(0, 42, "# now stack 0 is 42");

