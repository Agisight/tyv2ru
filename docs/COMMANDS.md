# Server Commands (ASCII-only for Proxmox console)

## Test
```
curl localhost:8077/health
bash scripts/test-quick.sh
```

## Manage
```
systemctl status tyv2ru-llama tyv2ru-api
systemctl restart tyv2ru-llama tyv2ru-api
systemctl stop tyv2ru-llama tyv2ru-api
```

## Logs
```
journalctl -u tyv2ru-llama -n 50
journalctl -u tyv2ru-api -n 50
```

## Update
```
cd /opt/translator/tyv2ru
git pull
bash scripts/deploy.sh
```

## Full reinstall
```
cd /opt/translator
rm -rf tyv2ru
git clone https://github.com/Agisight/tyv2ru.git
cd tyv2ru
bash scripts/deploy.sh
```
