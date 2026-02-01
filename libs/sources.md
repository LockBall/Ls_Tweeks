## LBB Addon – Embedded Library Sources

Created on: 26 Jan 2026  
Last updated: 26 Jan 2026 

---
Library: LibStub  
Notes: Lightweight versioning helper used by many older WoW libraries. Final, stable release.  
    GitHub repo is canonical and up to date.  
Source, pri: https://github.com/lua-wow/LibStub  
Source, alt: https://www.wowace.com/projects/libstub  
Depends on: (none)  
Required by: CallbackHandler, LibDataBroker, LibDBIcon  

---  
Library: CallbackHandler-1.0  
Notes: Event/callback dispatcher used internally by LibDataBroker and other libraries.  
    WowAce page is more up to date.  
Source, pri: https://www.wowace.com/projects/callbackhandler  
Source, alt: https://www.curseforge.com/wow/addons/callbackhandler  
Depends on: LibStub  
Required by: LibDataBroker  

---  
Library: LibDataBroker-1.1  
Notes: Core LDB library for creating data objects (e.g., minimap button launcher).  
Source, pri: https://www.wowace.com/projects/libdatabroker-1-1  
Source, alt: https://www.curseforge.com/wow/addons/libdatabroker-1-1  
Depends on: CallbackHandler  
Required by: LibDBIcon, LBB (for minimap button)  

---  
Library: LibDBIcon-1.0  
Notes: Handles minimap button creation, dragging, position saving, and visibility.  
    contains other libs, don't use unless certain of version  
Source, pri: https://www.wowace.com/projects/libdbicon-1-0  
Source, alt: https://www.curseforge.com/wow/addons/libdbicon-1-0  
Depends on: LibDataBroker, LibStub  
Required by: LBB (for minimap button) 