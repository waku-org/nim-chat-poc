## Utilties for development and debugging

proc dir*[T](obj: T) =
  echo "Object of type: ", T
  for name, value in fieldPairs(obj):
    echo "  ", name, ": ", value
