Redfish Walker
==============
Script walks through Redfish oids and collects data to ZIP archive into index.json files.

Script requires profile that specifies oids to collect.
You can use predefined profiles or create your own to collect just what you need.
Configuration profile supported in two formats .json and .profile and stored in profiles directory under script root folder

It has four sections:
- scan

Scrip walks through all oids found 
- tree

Script walks only throug parent tree
- once

Script collect oid once
- exclude

Oids that contain text from this section excluded

### Usage:


Clone repository or copy redfishWalker.ps1 to your PC.
Create or copy profiles directory in script root directory.
Create or copy profile file and put it to profiles directory.

You can run script with parameters or interactively.

Run using parameters:

`.\redfishWalker.ps1 -ipaddress <ipaddress> -user test -password test -walkprofile ilo5.profile`

Run interactively:

```
.\redfishWalker.ps1

redfishWalker v1.0 PS - walks through Redfish OIDs

Enter IP address: 10.10.10.10
Enter Username: hpadmin
Enter Password: ********
Enter Profile to use [default.profile]: ilo5.profile
```

### Requirements:
* Microsoft .NET 4.5 installed
* Tested on Windows 10 and PowerShell 5.1

### Author:
Sergii Oleshchenko<br/>
