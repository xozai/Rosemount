// Features/Settings/LicensesView.swift
// Rosemount
//
// Displays third-party open-source dependency attributions.
// Required by App Store legal guidelines when distributing apps that
// incorporate open-source libraries.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// MARK: - License model

private struct License: Identifiable {
    let id = UUID()
    let name: String
    let author: String
    let url: String
    let spdxId: String
    let licenseText: String
}

// MARK: - Data

private let licenses: [License] = [
    License(
        name: "swift-markdown",
        author: "Apple Inc.",
        url: "https://github.com/apple/swift-markdown",
        spdxId: "Apache-2.0",
        licenseText: """
        Copyright © 2021 Apple Inc. and the Swift project authors.
        Licensed under the Apache License, Version 2.0 (the "License");
        you may not use this file except in compliance with the License.
        You may obtain a copy of the License at
        http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software
        distributed under the License is distributed on an "AS IS" BASIS,
        WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
        See the License for the specific language governing permissions and
        limitations under the License.
        """
    ),
    License(
        name: "Nuke",
        author: "Alexander Grebenyuk",
        url: "https://github.com/kean/Nuke",
        spdxId: "MIT",
        licenseText: """
        Copyright © 2015-2024 Alexander Grebenyuk. All rights reserved.

        Permission is hereby granted, free of charge, to any person obtaining
        a copy of this software and associated documentation files (the
        "Software"), to deal in the Software without restriction, including
        without limitation the rights to use, copy, modify, merge, publish,
        distribute, sublicense, and/or sell copies of the Software, and to
        permit persons to whom the Software is furnished to do so, subject to
        the following conditions:

        The above copyright notice and this permission notice shall be included
        in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
        OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
        MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
        IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
        CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
        TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
        SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    ),
    License(
        name: "swift-collections",
        author: "Apple Inc.",
        url: "https://github.com/apple/swift-collections",
        spdxId: "Apache-2.0",
        licenseText: """
        Copyright © 2021 Apple Inc. and the Swift project authors.
        Licensed under the Apache License, Version 2.0 (the "License");
        you may not use this file except in compliance with the License.
        You may obtain a copy of the License at
        http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software
        distributed under the License is distributed on an "AS IS" BASIS,
        WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
        See the License for the specific language governing permissions and
        limitations under the License.
        """
    ),
    License(
        name: "KeychainAccess",
        author: "Kishikawa Katsumi",
        url: "https://github.com/kishikawakatsumi/KeychainAccess",
        spdxId: "MIT",
        licenseText: """
        Copyright © 2014 kishikawakatsumi. All rights reserved.

        Permission is hereby granted, free of charge, to any person obtaining
        a copy of this software and associated documentation files (the
        "Software"), to deal in the Software without restriction, including
        without limitation the rights to use, copy, modify, merge, publish,
        distribute, sublicense, and/or sell copies of the Software, and to
        permit persons to whom the Software is furnished to do so, subject to
        the following conditions:

        The above copyright notice and this permission notice shall be included
        in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
        OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
        MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
        IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
        CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
        TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
        SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    ),
]

// MARK: - Views

struct LicensesView: View {

    var body: some View {
        List(licenses) { license in
            NavigationLink {
                LicenseDetailView(license: license)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(license.name)
                        .font(.body)
                    HStack(spacing: 6) {
                        Text(license.author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(license.spdxId)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Open Source Licenses")
    }
}

private struct LicenseDetailView: View {
    let license: License

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(license.name)
                        .font(.title2.bold())
                    Text(license.spdxId)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Text(license.licenseText)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            .padding()
        }
        .navigationTitle(license.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let sourceURL = URL(string: license.url) {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: sourceURL) {
                        Label("Source", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
    }
}
