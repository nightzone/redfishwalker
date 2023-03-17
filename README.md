Redfish Walker
==============
Script walks through Redfish OIDs and collects data to ZIP archive into index.json files.

Script requires profile that specifies OIDs to collect.<br>
You can use predefined profiles or create your own to collect just what you need.<br>
Configuration profile supported in two formats `.json` and `.profile` and stored in `profiles` directory under script root folder.<br>

Profile has four sections:<br>
`scan`&emsp;Script walks through all oids found<br> 
`tree`&emsp;Script walks only throug parent tree<br>
`once`&emsp;Script collect oid once<br>
`exclude`&emsp;OIDs that contain text from this section excluded<br>

### Usage:

- Clone repository or copy redfishWalker.ps1 to your PC<br>
- Create or copy profiles directory to script root directory<br>
- Create or copy profile file and put it to profiles directory<br>

You can run script with parameters or interactively.

Run with parameters example:

```
.\redfishWalker.ps1 -ipaddress 10.10.10.10 -user test -password test -walkprofile ilo5.profile
```

Run interactively example:

```
.\redfishWalker.ps1

redfishWalker v1.0 PS - walks through Redfish OIDs

Enter IP address: 10.10.10.10
Enter Username: test
Enter Password: ****
Enter Profile to use [default.profile]: ilo5.profile
```

### Requirements:
* Microsoft .NET 4.5 installed
* Tested on Windows 10 and PowerShell 5.1

### Author:
Sergii Oleshchenko<br/>
