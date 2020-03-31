package data

// Data for OCS Config Files -------------------
//todo: is there a better way to handle this?

var PsiJson = `[
  {
    "module": "sdo_sys",
    "msg": "maxver",
    "value": "1"
  }
]`

var SviJson1 = `[
  {
    "module": "sdo_sys",
    "msg": "filedesc",
    "valueLen": -1,
    "valueId": "agent-install-crt_name",
    "enc": "base64"
  },
  {
    "module": "sdo_sys",
    "msg": "write",
    "valueLen": -1,
    "valueId": "agent-install.crt",
    "enc": "base64"
  },
  {
    "module": "sdo_sys",
   "msg": "filedesc",
   "valueLen": -1,
   "valueId": "agent-install-cfg_name",
   "enc": "base64"
  },
  {
    "module": "sdo_sys",
    "msg": "write",
    "valueLen": -1,
    "valueId": "agent-install.cfg",
    "enc": "base64"
  },
  {
    "module": "sdo_sys",
    "msg": "filedesc",
    "valueLen": -1,
    "valueId": "apt-repo-public-key_name",
    "enc": "base64"
  },
  {
    "module": "sdo_sys",
    "msg": "write",
    "valueLen": -1,
    "valueId": "apt-repo-public.key",
    "enc": "base64"
  },
  {
    "module": "sdo_sys",
    "msg": "filedesc",
    "valueLen": -1,
    "valueId": "agent-install-sh_name",
    "enc": "base64"
  },
  {
    "module": "sdo_sys",
    "msg": "write",
    "valueLen": -1,
    "valueId": "agent-install.sh",
    "enc": "base64"
  },
  {
    "module": "sdo_sys",
    "msg": "exec",
    "valueLen": -1,
    "valueId": "`

var SviJson2 = `_exec",
    "enc": "base64"
  }
]`
