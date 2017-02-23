%module pairinteraction

// Convert C++ exceptions to Python exceptions
// http://www.swig.org/Doc1.3/Library.html#Library_stl_exceptions
%include "exception.i"

%exception {
  try {
    $action
  } catch (const std::exception& e) {
    SWIG_exception(SWIG_RuntimeError, e.what());
  }
}

%{
#include "main.hpp"
%}

%include "std_string.i"
%include "main.hpp"