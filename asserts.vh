        assert_register("f", 7, "f:7     #now f is 7");
        assert_register("a", 42, "a:f*6   #now a is 42");
        assert_register("c", 8, "c:a/6+1 #now c is 8");
        assert_register("r", 10, "r:16    #now r is 10 hex because our radix is now 16.");
        assert_register("b", 15, "b:f     #now b is 15 not 1; a-f source digits, not variables");
        assert_register("r", 10, "r:a     #now r is 10 decimal; 'a' is 10 in hex, and we were in hex");
