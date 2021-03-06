# Copyright (c) 2016 Sebastian Weber, Henri Menke. All rights reserved.
#
# This file is part of the pairinteraction library.
#
# The pairinteraction library is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# The pairinteraction library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with the pairinteraction library. If not, see <http://www.gnu.org/licenses/>.

# Set compiler options for release builds

if(CMAKE_BUILD_TYPE MATCHES RELEASE)
  if(MSVC)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /Ox")
  else()
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Ofast -pipe")
  endif()
endif()

# Set /bigobj flag which is required for interface_[...]PYTHON_wrap.cxx

if(MSVC)
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /bigobj")
endif()

# Add current directory to search path

include_directories(${CMAKE_CURRENT_SOURCE_DIR})
include_directories(${CMAKE_CURRENT_BINARY_DIR})

# Generate in-memory database

file(READ databases/quantum_defects.sql QUANTUM_DEFECT_DATABASE_CONTENT)
configure_file(EmbeddedDatabase.h.in ${CMAKE_CURRENT_BINARY_DIR}/EmbeddedDatabase.h)

# Generate header containing the version informations
configure_file(version.h.in ${CMAKE_CURRENT_BINARY_DIR}/version.h)

# Add the executables

file(GLOB pairinteraction_SRCS *.cpp)
list(REMOVE_ITEM pairinteraction_SRCS ${CMAKE_CURRENT_SOURCE_DIR}/main.cpp)

add_library(pireal SHARED ${pairinteraction_SRCS})
add_library(picomplex SHARED ${pairinteraction_SRCS})
set_target_properties(picomplex PROPERTIES COMPILE_DEFINITIONS "USE_COMPLEX")

add_executable(pairinteraction-real    ${CMAKE_CURRENT_SOURCE_DIR}/main.cpp)
add_executable(pairinteraction-complex ${CMAKE_CURRENT_SOURCE_DIR}/main.cpp)

target_link_libraries(pairinteraction-real    pireal)
target_link_libraries(pairinteraction-complex picomplex)

if(MSVC)
  add_definitions(/W3 /DNOMINMAX /DWIN32_LEAN_AND_MEAN)
  #set_source_files_properties(${pairinteraction_SRCS} PROPERTIES COMPILE_FLAGS "/W3 /DNOMINMAX /DWIN32_LEAN_AND_MEAN")
else()
  set_source_files_properties(${pairinteraction_SRCS} PROPERTIES COMPILE_FLAGS "-Wall -Wextra -pedantic -Werror")
endif()

# Generate coverage report

if( WITH_COVERAGE )
  set(CMAKE_BUILD_TYPE "Debug" CACHE STRING "Choose the build type" FORCE)
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -g -O0 --coverage -fprofile-arcs -ftest-coverage")
  link_libraries(gcov)
endif( )

# Threads

find_package(Threads REQUIRED)
list(APPEND LIBRARIES ${CMAKE_THREAD_LIBS_INIT})

# Use OpenMP

find_package(OpenMPCXX)

if (OpenMPCXX_FOUND AND NOT WITH_CLANG_TIDY)
  list(APPEND LIBRARIES OpenMP::OpenMP_CXX)
else()
  message(WARNING "Because OpenMP was not found, calculations are not be parallelized.")
endif()

# Add external libraries

# Wigner Symbols
add_library(wignerSymbols ${CMAKE_SOURCE_DIR}/libs/wignerSymbols/src/wignerSymbols-cpp.cpp)
include_directories(SYSTEM ${CMAKE_SOURCE_DIR}/libs/wignerSymbols/include)
set_target_properties(wignerSymbols PROPERTIES CXX_CLANG_TIDY "" POSITION_INDEPENDENT_CODE ON)
list(APPEND LIBRARIES wignerSymbols)

# Include Eigen
include_directories(SYSTEM ${CMAKE_SOURCE_DIR}/libs/eigen)

find_package(Sqlite3 REQUIRED)
include_directories(SYSTEM ${SQLITE3_INCLUDE_DIR})
list(APPEND LIBRARIES ${SQLITE3_LIBRARY})

find_package(Boost COMPONENTS filesystem system program_options serialization REQUIRED)
include_directories(SYSTEM ${Boost_INCLUDE_DIRS})
list(APPEND LIBRARIES ${Boost_LIBRARIES})
if(MSVC)
  add_definitions(-DBOOST_ALL_NO_LIB)
  add_definitions(-DBOOST_ALL_DYN_LINK)
endif()

if(WITH_GSL)
  find_package(GSL REQUIRED)
  include_directories(SYSTEM ${GSL_INCLUDE_DIRS})
  list(APPEND LIBRARIES ${GSL_LIBRARIES})
  add_definitions(-DWITH_GSL)
endif()

find_package(MKL)
if (MKL_FOUND)
  include_directories(SYSTEM ${MKL_INCLUDE_DIR})
  list(APPEND LIBRARIES ${MKL_LIBRARY})
  add_definitions(-DWITH_INTEL_MKL)
endif()

target_link_libraries(pireal ${LIBRARIES})
target_link_libraries(picomplex ${LIBRARIES})

# Generate interface with SWIG
if(WITH_PYTHON)
  if(POLICY CMP0078)
    cmake_policy(SET CMP0078 OLD)
  endif()

  set( DATATYPE "real" )
  configure_file( Interface.i.cmakein ${CMAKE_CURRENT_BINARY_DIR}/interface_real.i )
  set( DATATYPE "complex" )
  configure_file( Interface.i.cmakein ${CMAKE_CURRENT_BINARY_DIR}/interface_complex.i )
  
  file( WRITE ${CMAKE_CURRENT_BINARY_DIR}/__init__.py "" )

  find_package(SWIG 3.0 REQUIRED)
  find_package(PythonInterp 3 REQUIRED)
  find_package(PythonLibs 3 REQUIRED)
  find_package(Numpy REQUIRED)

  include(${SWIG_USE_FILE})
  include_directories(SYSTEM ${PYTHON_INCLUDE_PATH})
  include_directories(SYSTEM ${NUMPY_INCLUDE_DIR})

  set_source_files_properties(${CMAKE_CURRENT_BINARY_DIR}/interface_real.i PROPERTIES CPLUSPLUS ON SWIG_FLAGS "-py3")
  if(COMMAND swig_add_library)
    swig_add_library(pireal LANGUAGE python SOURCES ${CMAKE_CURRENT_BINARY_DIR}/interface_real.i)
  else()
    swig_add_module(pireal python ${CMAKE_CURRENT_BINARY_DIR}/interface_real.i)
  endif()
  set_target_properties(_pireal PROPERTIES CXX_CLANG_TIDY "")
  if(APPLE)
    set_target_properties(_pireal PROPERTIES LINK_FLAGS "-undefined dynamic_lookup")
    swig_link_libraries(pireal pireal)
  elseif(MSVC)
    if(PYTHONLIBS_VERSION_STRING MATCHES "^3\\.([6-9]+)\\.[0-9]+([^0-9].*)?$")
        string(REPLACE "python3${CMAKE_MATCH_1}.lib" "python3.lib" PYTHON_LIBRARIES_GENERALIZED ${PYTHON_LIBRARIES})
    	set_target_properties(_pireal PROPERTIES LINK_FLAGS "/NODEFAULTLIB:python3${CMAKE_MATCH_1}.lib /DEFAULTLIB:python3.lib /FORCE:UNRESOLVED")
        swig_link_libraries(pireal pireal ${PYTHON_LIBRARIES_GENERALIZED})
    else()
        message(WARNING "The Windows version of the pairinteraction library will work with Python ${PYTHONLIBS_VERSION_STRING} only.")
        swig_link_libraries(pireal pireal ${PYTHON_LIBRARIES})
    endif()
  else()
    swig_link_libraries(pireal pireal)
  endif()
  
  set_source_files_properties(${CMAKE_CURRENT_BINARY_DIR}/interface_complex.i PROPERTIES CPLUSPLUS ON SWIG_FLAGS "-py3;-DUSE_COMPLEX")
  if(COMMAND swig_add_library)
    swig_add_library(picomplex LANGUAGE python SOURCES ${CMAKE_CURRENT_BINARY_DIR}/interface_complex.i)
  else()
    swig_add_module(picomplex python ${CMAKE_CURRENT_BINARY_DIR}/interface_complex.i)
  endif()
  set_source_files_properties( ${swig_generated_file_fullname} PROPERTIES COMPILE_DEFINITIONS "USE_COMPLEX")
  set_target_properties(_picomplex PROPERTIES CXX_CLANG_TIDY "")
  if(APPLE)
    set_target_properties(_picomplex PROPERTIES LINK_FLAGS "-undefined dynamic_lookup")
    swig_link_libraries(picomplex picomplex)
  elseif(MSVC)
    if(PYTHONLIBS_VERSION_STRING MATCHES "^3\\.([6-9]+)\\.[0-9]+([^0-9].*)?$")
        string(REPLACE "python3${CMAKE_MATCH_1}.lib" "python3.lib" PYTHON_LIBRARIES_GENERALIZED ${PYTHON_LIBRARIES})
    	set_target_properties(_picomplex PROPERTIES LINK_FLAGS "/NODEFAULTLIB:python3${CMAKE_MATCH_1}.lib /DEFAULTLIB:python3.lib /FORCE:UNRESOLVED")
        swig_link_libraries(picomplex picomplex ${PYTHON_LIBRARIES_GENERALIZED})
    else()
        message(WARNING "The Windows version of the pairinteraction library will work with Python ${PYTHONLIBS_VERSION_STRING} only.")
        swig_link_libraries(picomplex picomplex ${PYTHON_LIBRARIES})
    endif()
  else()
    swig_link_libraries(picomplex picomplex)
  endif()
endif()

# Include test cases

add_subdirectory( unit_test )

# CPack

if( WITH_DMG )
  find_package(PythonInterp 3 REQUIRED)

  if(WITH_PYTHON)
    install(TARGETS _pireal LIBRARY DESTINATION ${LIBNAME})
    install(TARGETS _picomplex LIBRARY DESTINATION ${LIBNAME})
    install(FILES ${CMAKE_CURRENT_BINARY_DIR}/pireal.py DESTINATION ${LIBNAME})
    install(FILES ${CMAKE_CURRENT_BINARY_DIR}/picomplex.py DESTINATION ${LIBNAME})
  endif()
  install(TARGETS pireal LIBRARY DESTINATION ${LIBNAME})
  install(TARGETS picomplex LIBRARY DESTINATION ${LIBNAME})
  install(TARGETS pairinteraction-real RUNTIME DESTINATION ${LIBNAME})
  install(TARGETS pairinteraction-complex RUNTIME DESTINATION ${LIBNAME})

  set(bin1 \${CMAKE_INSTALL_PREFIX}/${LIBNAME}/libpireal.dylib)
  set(bin2 \${CMAKE_INSTALL_PREFIX}/${LIBNAME}/libpicomplex.dylib)
  set(bin3 \${CMAKE_INSTALL_PREFIX}/${LIBNAME}/pairinteraction-real)
  set(bin4 \${CMAKE_INSTALL_PREFIX}/${LIBNAME}/pairinteraction-complex)
  if(WITH_PYTHON)
    set(bin5 \${CMAKE_INSTALL_PREFIX}/${LIBNAME}/_pireal.so)
    set(bin6 \${CMAKE_INSTALL_PREFIX}/${LIBNAME}/_picomplex.so)
  endif()
  
  install(CODE "execute_process(COMMAND ${PYTHON_EXECUTABLE} ${CMAKE_MACOSX_GOODIES_PATH}/standalone.py \${CMAKE_INSTALL_PREFIX}/${LIBNAME}/libraries ${bin1} ${bin2} ${bin3} ${bin4} ${bin5} ${bin6})")

elseif ( NOT WIN32 )

  if(WITH_PYTHON)
    set(PY_VERSION "${PYTHON_VERSION_MAJOR}.${PYTHON_VERSION_MINOR}")
    set(PY_MOD_DIR "lib/python${PY_VERSION}/dist-packages/${LIBNAME}")

    install(TARGETS _pireal    LIBRARY DESTINATION ${PY_MOD_DIR})
    install(TARGETS _picomplex LIBRARY DESTINATION ${PY_MOD_DIR})
    install(FILES ${CMAKE_CURRENT_BINARY_DIR}/pireal.py    DESTINATION ${PY_MOD_DIR})
    install(FILES ${CMAKE_CURRENT_BINARY_DIR}/picomplex.py DESTINATION ${PY_MOD_DIR})
  endif()

  install(TARGETS pireal    LIBRARY DESTINATION lib)
  install(TARGETS picomplex LIBRARY DESTINATION lib)
  install(TARGETS pairinteraction-real    RUNTIME DESTINATION share/pairinteraction/${LIBNAME})
  install(TARGETS pairinteraction-complex RUNTIME DESTINATION share/pairinteraction/${LIBNAME})

endif( )
