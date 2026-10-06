# Libraries

Copies of other authors' libraries, for the minimap icon (LibDBIcon-1.0 and what it needs). Seek's TOC loads them before Seek's own files. Do not change them here; to update one, copy the new release from its source below and change its line here. luacheck skips this folder. Moving them to `.pkgmeta` externals is issue #51.

| Library | Version | Source | License |
| --- | --- | --- | --- |
| LibStub | tag `1.0.3-50001` (LibStub minor 2), SVN r76 | https://repos.wowace.com/wow/libstub/tags/1.0.3-50001/LibStub.lua | Public domain (says so in `LibStub.lua`) |
| CallbackHandler-1.0 | tag `1.0.9` (minor 8), SVN r26 | https://repos.wowace.com/wow/callbackhandler/tags/1.0.9/CallbackHandler-1.0/CallbackHandler-1.0.lua | BSD, Ace3 Development Team: `CallbackHandler-1.0/LICENSE.txt` |
| LibDataBroker-1.1 | tag `v1.1.4` (minor 4), commit `1a63ede0248c11aa1ee415187c1f9c9489ce3e02` | https://github.com/tekkub/libdatabroker-1-1 | None given upstream |
| LibDBIcon-1.0 | tag `v12.0.3` (minor 56), SVN r155 | https://repos.wowace.com/wow/libdbicon-1-0/tags/v12.0.3/LibDBIcon-1.0/LibDBIcon-1.0.lua | "All Rights Reserved" (the `X-License` line of its TOC); made to be embedded in addons |

Only the Lua files are copied, not the libraries' own TOC and XML files. Upstream has no license file for LibStub, LibDataBroker-1.1 or LibDBIcon-1.0. CallbackHandler-1.0's own repository has none either; its TOC says BSD, and `LICENSE.txt` is the license of Ace3 (https://repos.wowace.com/wow/ace3/trunk/LICENSE.txt), whose team writes it and which ships the same file.
