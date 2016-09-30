//
//  LoadableCategory.h
//  GRToolkit
//
//  Created by Grant Robinson on 8/28/13.
//  Copyright (c) 2013 Grant Robinson. All rights reserved.
//

#ifndef GRToolkit_LoadableCategory_h
#define GRToolkit_LoadableCategory_h

/** Make all categories in the current file loadable without using -load-all.
 *
 * Normally, compilers will skip linking files that contain only categories.
 * Adding a call to this macro adds a dummy class, which causes the linker
 * to add the file.
 *
 * @param UNIQUE_NAME A globally unique name.
 */
#define MAKE_CATEGORIES_LOADABLE(UNIQUE_NAME) @interface FORCELOAD_##UNIQUE_NAME : NSObject @end @implementation FORCELOAD_##UNIQUE_NAME @end


#endif
