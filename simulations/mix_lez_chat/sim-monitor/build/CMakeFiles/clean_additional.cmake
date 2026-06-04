# Additional clean files
cmake_minimum_required(VERSION 3.16)

if("${CONFIG}" STREQUAL "" OR "${CONFIG}" STREQUAL "")
  file(REMOVE_RECURSE
  "CMakeFiles/sim-monitor_autogen.dir/AutogenUsed.txt"
  "CMakeFiles/sim-monitor_autogen.dir/ParseCache.txt"
  "sim-monitor_autogen"
  )
endif()
