/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

import MobileDevelopmentKit

extension NXBuilder: MDKDriverDelegate {
    func driver(_ driver: MDKDriver,
                outputPathForInputFile file: MDKFile) -> String? {
        return "\(self.project.cacheURL.path)/\(NXExpectedObjectFileURLForFileURL(NXRelativeURLFromBaseURLToFullURL(self.project.url, file.fileURL)).path)"
    }
    
    func driver(_ driver: MDKDriver,
                skipCompileForInputFile file: MDKFile) -> Bool {
        if !CCFileTypeIsSwiftFile(file.type),
           !self.projectDirty {
            
            let path: String = file.fileURL.path
            let objectPath = "\(self.project.cacheURL.path)/\(NXExpectedObjectFileURLForFileURL(NXRelativeURLFromBaseURLToFullURL(self.project.url, file.fileURL)).path)"
            
            // Checking if the source file is newer than the compiled object file
            guard let sourceDate = try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date,
                  let objectDate = try? FileManager.default.attributesOfItem(atPath: objectPath)[.modificationDate] as? Date,
                  objectDate > sourceDate else {
                self.database.removeFileDebug(ofPath: file.fileURL.path)
                return false
            }
            
            // Checking if the header files included by the source code are newer than the object file
            guard let headers = self.dependencyScanner.headerFiles(for: file) else {
                self.database.removeFileDebug(ofPath: file.fileURL.path)
                return false
            }
            
            for header in headers {
                guard let fileURL = header.fileURL,
                      let headerDate = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date,
                      objectDate > headerDate else {
                    self.database.removeFileDebug(ofPath: file.fileURL.path)
                    return false
                }
            }
            
            return true
        } else {
            self.database.removeFileDebug(ofPath: file.fileURL.path)
            return false
        }
    }
}
