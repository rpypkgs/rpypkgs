
++++++ number 1
>
+++++++ number 2
<
[ outer adder loop
  > copy second looping number
  [
    >+ real copy
    >+ backup to copy to original
    <<- decrement
  ]

  >> restore second loop after copy
  [
    <<+
    >>-
  ]
  < set pointer to helper secondary loop num

  [ do the incrementation (multiply)
    >>+
    <<-
  ]
  <<-
]
>>>>.
