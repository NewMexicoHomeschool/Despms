# Hostinger — DezPMS install

Hostinger has the **strongest affiliate %** for India / SEA hotels and the
weakest official ISV 1-click. Until they accept a VPS template, the path is:

1. Create **KVM 2** (2 vCPU / 8 GB) · **Ubuntu 24.04 with Docker** via the
   DezPMS referral link <https://www.hostinger.com/in?REFERRALCODE=DezPMSpms>
   (buyer saves **20%**, or coupon **`DezPMSPMS`**; using the link helps keep
   DezPMS afloat). Same URL as the website's `src/data/affiliates.ts`.
2. Point `pms.yourhotel.com` A-record at the VPS IP.
3. hPanel → VPS → **Browser terminal** (or SSH) and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/DezPMS-PMS/DezPMS-pms/main/deploy/install.sh | bash
```

4. Answer site domain, admin email, admin password.
5. Put TLS in front (`certbot --nginx -d pms.yourhotel.com`) or Hostinger's panel proxy.
6. Open `/DezPMS/setup`. Update later with `sudo /opt/DezPMS/install.sh update`.

Hostinger's VPS "templates" catalogue is Hostinger-curated; once DezPMS has
traction, apply to get a DezPMS template listed so this becomes a true
one-click.

## Affiliate

Hostinger affiliate often **~40%+** of first sale (tiered); Partner program
**~20% new + 10% renewals**. Keep the affiliate ID only in website config
(`affiliates.ts`), never hard-coded in docs partners copy-paste.
