# The official embedded package is pinned and checksum-verified at configure
# time. The application never fetches executable widget code at runtime.
set(PRISM_ELEMENT_CALL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/element-call/dist"
    CACHE PATH "Built PrismChat embedded Element Call assets")
if(NOT EXISTS "${PRISM_ELEMENT_CALL_DIR}/index.html")
    find_package(Python3 REQUIRED COMPONENTS Interpreter)
    execute_process(
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/scripts/fetch-element-call.py"
            --output "${CMAKE_CURRENT_SOURCE_DIR}/third_party/element-call"
        RESULT_VARIABLE PRISM_ELEMENT_CALL_FETCH_RESULT
    )
    if(NOT PRISM_ELEMENT_CALL_FETCH_RESULT EQUAL 0)
        message(FATAL_ERROR "Unable to fetch the pinned Element Call embedded bundle")
    endif()
endif()
file(GLOB_RECURSE PRISM_ELEMENT_CALL_FILES CONFIGURE_DEPENDS
    RELATIVE "${PRISM_ELEMENT_CALL_DIR}" "${PRISM_ELEMENT_CALL_DIR}/*")
set(PRISM_ELEMENT_CALL_QRC "${CMAKE_CURRENT_BINARY_DIR}/element-call.qrc")
set(PRISM_ELEMENT_CALL_XML "<RCC><qresource prefix=\"/element-call\">\n")
foreach(asset IN LISTS PRISM_ELEMENT_CALL_FILES)
    string(APPEND PRISM_ELEMENT_CALL_XML "<file alias=\"${asset}\">${PRISM_ELEMENT_CALL_DIR}/${asset}</file>\n")
endforeach()
string(APPEND PRISM_ELEMENT_CALL_XML "</qresource></RCC>\n")
file(WRITE "${PRISM_ELEMENT_CALL_QRC}" "${PRISM_ELEMENT_CALL_XML}")
