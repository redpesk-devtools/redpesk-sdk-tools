# Pre-authorizing devices on Mender server

## Generate a key pair for device pre-authorization

To initiate the pre-authorization process for a device, we require two crucial pieces of information from the device:

    1. The device's identity, which includes its MAC address and device type.
    2. The device's public key.

To ensure the security and randomness of the keys, we will generate them on a separate system, not on the device itself.
Once generated, these keys will be placed into the device's storage. This approach enables us to maintain records of the device's public key and guarantees a satisfactory level of entropy during key creation, thereby producing highly secure and random keys.

For the generation of a keypair that is comprehensible to the Mender client running on the target, we will employ a script. This script utilizes the "openssl" command to produce the keys. To acquire the script, download it to a designated directory using the following command:

```bash
wget https://raw.githubusercontent.com/redpesk-devtools/redpesk-sdk-tools/master/generate-device-preauth-keys.sh
```

After downloading, ensure that the script has executable permissions:

```bash
chmod +x generate-device-preauth-keys.sh
```

Finally, execute the script as follows:

```bash
./generate-device-preauth-keys.sh -o <path_to_output_directory>
```

The resulting Mender client keypair will be located in your specified output directory within a subdirectory named "keys-client-generated":

```
output_directory
└──keys-client-generated/
    ├── mender-agent.pem
    └── public.key
```

## Device Pre-authorization

Now that we possess both the device's identity and its public key, we will utilize the Redpesk UI to pre-authorize the device.

## Transferring the Generated Device Key to Your Device

Following the key generation and pre-authorization, the subsequent task is to move the newly created private key to your device. This private key should be placed in its default destination at /var/lib/mender/mender-agent.pem.


**Important to note** :

    * Prior installation of the mender-client on your device is assumed.
    * Ensure that the mender-client is not already running on your device.

After successfully transferring the private key to the designated location on your device, the next step is to set the device type and start the mender-client service.

```bash
mkdir /var/lib/mender  # Execute only if the directory doesn't exist yet
device_type="<Type_de_device>"
echo "device_type=$device_type" > /var/lib/mender/device_type

# Start mender-client service
systemctl start mender-client
```

