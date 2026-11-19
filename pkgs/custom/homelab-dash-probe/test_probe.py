import unittest
from unittest.mock import patch
import probe


class ProbeTests(unittest.TestCase):
    def test_identity_does_not_disclose_identifiers_or_claim_provisioning(self):
        body = (f'<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">'
                f'<s:Body><i:IdentifyResponse xmlns:i="{probe.IDENTIFY_NS}">'
                '<i:ProductVersion>PRIVATE</i:ProductVersion>'
                '</i:IdentifyResponse></s:Body></s:Envelope>').encode()
        result = probe.classify(200, body)
        self.assertTrue(result['wsman_identity'])
        self.assertEqual(result['provisioning'], 'unknown')
        self.assertNotIn('PRIVATE', str(result))

    def test_unauthorized_is_not_provisioning_evidence(self):
        result = probe.classify(401, b'PRIVATE')
        self.assertTrue(result['authentication_required'])
        self.assertEqual(result['provisioning'], 'unknown')

    def test_malformed_and_unrelated_xml(self):
        self.assertEqual(probe.classify(200, b'<')['error'], 'invalid_xml')
        self.assertFalse(probe.classify(200, b'<unrelated/>')['wsman_identity'])
        self.assertEqual(probe.classify(200, b'<!DOCTYPE x><x/>')['error'],
                         'forbidden_xml_declaration')

    @patch('probe.http.client.HTTPConnection')
    def test_only_identify_no_auth_and_no_redirect_following(self, factory):
        response = factory.return_value.getresponse.return_value
        response.status = 302
        response.read.return_value = b''
        result = probe.probe('192.0.2.8', 623, 1)
        self.assertEqual(result['http_status'], 302)
        args = factory.return_value.request.call_args.args
        self.assertEqual(args[:2], ('POST', '/wsman'))
        self.assertIn(b'<i:Identify ', args[2])
        self.assertNotIn('Authorization', args[3])
        factory.return_value.close.assert_called_once()

    @patch('probe.http.client.HTTPConnection')
    def test_bound_response_and_errors(self, factory):
        response = factory.return_value.getresponse.return_value
        response.read.return_value = b'x' * (probe.MAX_RESPONSE + 1)
        self.assertEqual(probe.probe('192.0.2.8', 623, 1)['error'], 'response_too_large')
        factory.return_value.request.side_effect = TimeoutError('PRIVATE')
        self.assertEqual(probe.probe('192.0.2.8', 623, 1)['error'], 'TimeoutError')

    def test_reject_url(self):
        with self.assertRaises(ValueError):
            probe.probe('http://example.com', 623, 1)


if __name__ == '__main__':
    unittest.main()
