// OpenMoney WebAuthn Passkeys Helper
(function() {
  function b64ToUint8(b64) {
    let str = b64.replace(/-/g, "+").replace(/_/g, "/");
    while (str.length % 4 !== 0) str += "=";
    const bin = atob(str);
    const arr = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
    return arr;
  }

  function uint8ToB64Url(uint8) {
    let bin = "";
    for (let i = 0; i < uint8.length; i++) bin += String.fromCharCode(uint8[i]);
    return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }

  window.openmoneyPasskeyIsSupported = function() {
    return !!(window.PublicKeyCredential && window.navigator && window.navigator.credentials);
  };

  window.openmoneyPasskeyRegister = async function(optionsJson) {
    try {
      const opts = JSON.parse(optionsJson);
      opts.challenge = b64ToUint8(opts.challenge);
      opts.user.id = b64ToUint8(opts.user.id);
      if (opts.excludeCredentials && Array.isArray(opts.excludeCredentials)) {
        opts.excludeCredentials.forEach(function(c) { c.id = b64ToUint8(c.id); });
      }

      const cred = await navigator.credentials.create({ publicKey: opts });
      if (!cred) throw new Error("Criação de chave-senha cancelada.");

      const rawId = uint8ToB64Url(new Uint8Array(cred.rawId));
      const clientDataJSON = uint8ToB64Url(new Uint8Array(cred.response.clientDataJSON));
      const attestationObject = uint8ToB64Url(new Uint8Array(cred.response.attestationObject));

      let publicKeySpki = "";
      if (typeof cred.response.getPublicKey === "function") {
        const pkBuf = cred.response.getPublicKey();
        if (pkBuf) publicKeySpki = uint8ToB64Url(new Uint8Array(pkBuf));
      }

      return JSON.stringify({
        ok: true,
        credentialId: cred.id,
        rawId: rawId,
        clientDataJSON: clientDataJSON,
        attestationObject: attestationObject,
        publicKeySpki: publicKeySpki
      });
    } catch (err) {
      return JSON.stringify({ ok: false, error: err.message || String(err) });
    }
  };

  window.openmoneyPasskeyLogin = async function(optionsJson) {
    try {
      const opts = JSON.parse(optionsJson);
      opts.challenge = b64ToUint8(opts.challenge);
      if (opts.allowCredentials && Array.isArray(opts.allowCredentials)) {
        opts.allowCredentials.forEach(function(c) { c.id = b64ToUint8(c.id); });
      }

      const assertion = await navigator.credentials.get({ publicKey: opts });
      if (!assertion) throw new Error("Autenticação com chave-senha cancelada.");

      const rawId = uint8ToB64Url(new Uint8Array(assertion.rawId));
      const clientDataJSON = uint8ToB64Url(new Uint8Array(assertion.response.clientDataJSON));
      const authenticatorData = uint8ToB64Url(new Uint8Array(assertion.response.authenticatorData));
      const signature = uint8ToB64Url(new Uint8Array(assertion.response.signature));

      let userHandle = null;
      if (assertion.response.userHandle) {
        userHandle = uint8ToB64Url(new Uint8Array(assertion.response.userHandle));
      }

      return JSON.stringify({
        ok: true,
        credentialId: assertion.id,
        rawId: rawId,
        clientDataJSON: clientDataJSON,
        authenticatorData: authenticatorData,
        signature: signature,
        userHandle: userHandle
      });
    } catch (err) {
      return JSON.stringify({ ok: false, error: err.message || String(err) });
    }
  };
})();
