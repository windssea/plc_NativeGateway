FUNCTION NG_Add4 : DWORD
VAR_INPUT
    a : DWORD;
    b : DWORD;
    c : DWORD;
    d : DWORD;
END_VAR
(* Four uint32 operands fit uint64. A mask implements modulo 2^32 without
   software uint64 division on the AXC F 2152 ARM target. *)
NG_Add4 := TO_DWORD(TO_LWORD(TO_ULINT(a)+TO_ULINT(b)+TO_ULINT(c)+TO_ULINT(d)) AND LWORD#16#FFFFFFFF);
END_FUNCTION
