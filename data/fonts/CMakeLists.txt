# -*- mode: CMake; cmake-tab-width: 4; -*-

if(WXM_INCLUDE_FONTS)
    file(GLOB fontfiles *.ttf *.otf)
    file(GLOB fontlicensefiles COPYING-*.txt)

    file(COPY ${fontfiles} ${fontlicensefiles} DESTINATION ${CMAKE_BINARY_DIR}/share/wxMaxima/fonts) # used by ./wxmaxima-local
    install(FILES ${fontfiles} ${fontlicensefiles} DESTINATION share/wxMaxima/fonts)

    file(WRITE "${CMAKE_BINARY_DIR}/addprivatefonts.h"
        "#ifndef ADDPRIVATEFONTS_H\n"
        "#define ADDPRIVATEFONTS_H\n"
        "#include <wx/version.h>\n"
        "#include <wx/font.h>\n"
        "void addprivatefonts() {\n"
        "    #if wxCHECK_VERSION(3, 1, 1)\n")
    foreach(currentfont ${fontfiles})
    get_filename_component(fontname "${currentfont}" NAME)
    file(APPEND "${CMAKE_BINARY_DIR}/addprivatefonts.h"
        "    if (wxFileExists(\"${CMAKE_INSTALL_PREFIX}/share/wxMaxima/fonts/${fontname}\")) wxFont::AddPrivateFont(\"${CMAKE_INSTALL_PREFIX}/share/wxMaxima/fonts/${fontname}\");\n"
        "    if (wxFileExists(\"share/wxMaxima/fonts/${fontname}\")) wxFont::AddPrivateFont(\"share/wxMaxima/fonts/${fontname}\"); /* used by ./wxmaxima-local */ \n")
    endforeach()
    file(APPEND "${CMAKE_BINARY_DIR}/addprivatefonts.h"
        "    #endif\n"
        "}\n"
        "#endif\n")
endif()
