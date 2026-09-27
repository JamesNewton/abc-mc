        assert_register("f", 7, "f:7       #now f is 7");
        assert_register("g", 10, "g:f+3     #now g is 10 Basic addition");
        assert_register("h", 6, "h:g-4     #now h is 6 and subtraction");
        assert_register("i", 7, "i:h&4|1^2 #now i is 7 Binary and, or, and xor");
        assert_register("a", 42, "a:i*6     #now a is 42 Multiplication");
        assert_register("c", 8, "c:a/6+1   #now c is 8 Division (integer)");
        assert_register("r", 10, "r:16      #now r is 10 hex because our radix is now 16.");
        assert_register("b", 15, "b:f       #now b is 15 not 7; a-f source digits, not variables");
        assert_register("r", 10, "r:a       #now r is 10 decimal; 'a' is 10 in hex, and we were in hex");
