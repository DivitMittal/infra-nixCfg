"""Unauthenticated WS-Man Identify only; does not infer provisioning from ports."""
import argparse
import http.client
import ipaddress
import json
import ssl
import xml.etree.ElementTree as ET

IDENTIFY_NS = "http://schemas.dmtf.org/wbem/wsman/identity/1/wsmanidentity.xsd"
SOAP = (f'<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">'
        f'<s:Header/><s:Body><i:Identify xmlns:i="{IDENTIFY_NS}"/>'
        '</s:Body></s:Envelope>').encode()
MAX_RESPONSE = 65536


def classify(status, body):
    result = {"http_status": status, "wsman_identity": False,
              "authentication_required": status == 401, "provisioning": "unknown"}
    if status != 200:
        return result
    # No arbitrary text or XML properties are printed: they may identify a unit.
    if b"<!DOCTYPE" in body.upper() or b"<!ENTITY" in body.upper():
        result["error"] = "forbidden_xml_declaration"
        return result
    try:
        root = ET.fromstring(body)
    except ET.ParseError:
        result["error"] = "invalid_xml"
        return result
    result["wsman_identity"] = root.find(f".//{{{IDENTIFY_NS}}}IdentifyResponse") is not None
    return result


def probe(address, port, timeout):
    # Literal addresses prevent URL credentials, paths, redirects and DNS surprises.
    ipaddress.ip_address(address)
    connection = (http.client.HTTPSConnection(address, port, timeout=timeout,
                  context=ssl.create_default_context()) if port == 664 else
                  http.client.HTTPConnection(address, port, timeout=timeout))
    try:
        connection.request("POST", "/wsman", SOAP,
                           {"Content-Type": "application/soap+xml;charset=UTF-8"})
        response = connection.getresponse()
        body = response.read(MAX_RESPONSE + 1)
        if len(body) > MAX_RESPONSE:
            return {"error": "response_too_large", "provisioning": "unknown"}
        return classify(response.status, body)
    except (OSError, http.client.HTTPException) as exc:
        return {"error": type(exc).__name__, "provisioning": "unknown"}
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("address", type=ipaddress.ip_address)
    parser.add_argument("--port", type=int, choices=(623, 664), default=664)
    args = parser.parse_args()
    result = probe(str(args.address), args.port, 3)
    print(json.dumps(result, sort_keys=True))
    return 0 if result.get("wsman_identity") else 2


if __name__ == "__main__":
    raise SystemExit(main())
