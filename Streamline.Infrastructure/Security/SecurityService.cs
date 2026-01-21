using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

using Streamline.Core.Interfaces;

namespace Streamline.Infrastructure.Security
{
    public class SecurityService : ISecurityService
    {
        // In a real production app, this key should come from an environment variable or a secure vault.
        // For this specific request, we'll use a machine-specific or hardcoded fallback if env is missing
        // to ensure it works on the Pi without complex KMS setup.
        
        private readonly byte[] _key;
        private readonly byte[] _iv;

        public SecurityService(string masterKeyString)
        {
            // Derive a consistent key/IV from the provided string (e.g. machine ID or user input)
            using (var sha256 = SHA256.Create())
            {
                _key = sha256.ComputeHash(Encoding.UTF8.GetBytes(masterKeyString));
                _iv = sha256.ComputeHash(Encoding.UTF8.GetBytes(masterKeyString + "_iv"));
                Array.Resize(ref _iv, 16); // AES needs 16 bytes IV
            }
        }

        public string Encrypt(string plainText)
        {
            if (string.IsNullOrEmpty(plainText)) return "";

            using (var aes = Aes.Create())
            {
                aes.Key = _key;
                aes.IV = _iv;

                using (var encryptor = aes.CreateEncryptor(aes.Key, aes.IV))
                using (var ms = new MemoryStream())
                {
                    using (var cs = new CryptoStream(ms, encryptor, CryptoStreamMode.Write))
                    using (var sw = new StreamWriter(cs))
                    {
                        sw.Write(plainText);
                    }
                    return Convert.ToBase64String(ms.ToArray());
                }
            }
        }

        public string Decrypt(string cipherText)
        {
            if (string.IsNullOrEmpty(cipherText)) return "";

            try
            {
                using (var aes = Aes.Create())
                {
                    aes.Key = _key;
                    aes.IV = _iv;

                    using (var decryptor = aes.CreateDecryptor(aes.Key, aes.IV))
                    using (var ms = new MemoryStream(Convert.FromBase64String(cipherText)))
                    using (var cs = new CryptoStream(ms, decryptor, CryptoStreamMode.Read))
                    using (var sr = new StreamReader(cs))
                    {
                        return sr.ReadToEnd();
                    }
                }
            }
            catch
            {
                return ""; // Fail gracefully
            }
        }
    }
}
