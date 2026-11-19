"use client";

import { useState } from "react";

export default function CopyReferralLink({ url }: { url: string }) {
  const [copied, setCopied] = useState(false);
  const [failed, setFailed] = useState(false);

  async function copy() {
    setCopied(false);
    setFailed(false);
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
    } catch {
      setFailed(true);
    }
  }

  return (
    <div className="copy-row">
      <button className="copy-button" type="button" onClick={copy}>Copier le lien</button>
      {copied && <span className="copy-feedback" role="status">Lien copié</span>}
      {failed && <span className="copy-feedback copy-error" role="status">Copie indisponible dans ce navigateur</span>}
    </div>
  );
}
