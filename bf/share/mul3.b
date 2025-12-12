> ++            Write 2 in T1
> +++           Write 3 in T2

<               Goto T1
[               While T1 is nonzero
  >             Goto T2
  [->+>+<<]     Copy T2 to T3 and T4
  >>            Goto to T4
  [-<<+>>]      Move T4 to T2
  <             Goto to T3
  [-<<<+>>>]    Accumulate T3 onto T0
  <<            Goto to T1
  -             Decrement T1
]

< [.-]         Emit T0
