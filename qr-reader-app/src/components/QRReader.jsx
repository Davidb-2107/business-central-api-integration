import { useState } from 'react'
import '../styles/QRReader.css'

/**
 * QRReader Component
 *
 * Affiche les données extraites d'un QR-code de facture suisse
 * et permet l'ajout d'un champ Mandat optionnel avant envoi à Business Central.
 *
 * Le champ Mandat correspond au numéro de client chez le fournisseur
 * (ex: "Client N° : 764" sur la facture).
 */
function QRReader() {
  // État pour les données QR parsées (simulées ou reçues d'un scanner)
  const [parsedData, setParsedData] = useState({
    companyName: '',
    street: '',
    buildingNumber: '',
    postalCode: '',
    city: '',
    country: 'CH',
    amount: 0,
    currency: 'CHF',
    reference: '',
    payment_reference: '',
    'qr_reference_(qrr)': ''
  })

  // État pour le champ Mandat (optionnel)
  const [mandat, setMandat] = useState('')

  // État pour le statut d'envoi
  const [sending, setSending] = useState(false)
  const [sendStatus, setSendStatus] = useState(null)

  // URL du webhook n8n (à configurer)
  const WEBHOOK_URL = import.meta.env.VITE_WEBHOOK_URL || ''

  /**
   * Gestion de la saisie du fichier PDF/image QR
   * Dans une implémentation réelle, utiliser une librairie de scan QR
   */
  const handleFileChange = async (event) => {
    const file = event.target.files?.[0]
    if (!file) return

    // Simulation de données extraites - à remplacer par un vrai parser QR
    // Dans la vraie implémentation, utiliser une librairie comme jsQR ou qr-scanner
    setParsedData({
      companyName: 'CENTRE PATRONAL',
      street: 'Route du Lac',
      buildingNumber: '2',
      postalCode: '1094',
      city: 'Paudex',
      country: 'CH',
      amount: 18250.00,
      currency: 'CHF',
      reference: '22506271',
      payment_reference: '000000000000002250627109240',
      'qr_reference_(qrr)': '000000000000002250627109240'
    })

    setSendStatus(null)
  }

  /**
   * Envoi des données vers le webhook n8n
   * Inclut le champ mandat dans le payload
   */
  const handleSubmit = async (event) => {
    event.preventDefault()

    if (!WEBHOOK_URL) {
      setSendStatus({
        success: false,
        message: 'URL du webhook non configurée. Définissez VITE_WEBHOOK_URL.'
      })
      return
    }

    setSending(true)
    setSendStatus(null)

    // Construction du payload avec le champ mandat
    const payload = {
      parsedData: {
        ...parsedData,
        mandat: mandat.trim()
      }
    }

    try {
      const response = await fetch(WEBHOOK_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      })

      if (response.ok) {
        setSendStatus({
          success: true,
          message: 'Facture envoyée avec succès vers Business Central'
        })
        // Réinitialiser le formulaire après succès
        setMandat('')
      } else {
        throw new Error(`Erreur HTTP: ${response.status}`)
      }
    } catch (error) {
      setSendStatus({
        success: false,
        message: `Erreur lors de l'envoi: ${error.message}`
      })
    } finally {
      setSending(false)
    }
  }

  /**
   * Formate le montant pour l'affichage
   */
  const formatAmount = (amount, currency) => {
    return new Intl.NumberFormat('fr-CH', {
      style: 'currency',
      currency: currency || 'CHF'
    }).format(amount)
  }

  const hasData = parsedData.companyName !== ''

  return (
    <div className="qr-reader">
      <header className="qr-reader__header">
        <h1>QR-Reader</h1>
        <p className="qr-reader__subtitle">Scanner de factures QR suisses</p>
      </header>

      <form onSubmit={handleSubmit} className="qr-reader__form">
        {/* Section upload fichier */}
        <section className="qr-reader__section">
          <h2>Scanner une facture</h2>
          <div className="qr-reader__upload">
            <input
              type="file"
              id="qr-file"
              accept=".pdf,image/*"
              onChange={handleFileChange}
              className="qr-reader__file-input"
            />
            <label htmlFor="qr-file" className="qr-reader__file-label">
              Sélectionner un fichier PDF ou image
            </label>
          </div>
        </section>

        {/* Section données extraites */}
        {hasData && (
          <>
            <section className="qr-reader__section">
              <h2>Données extraites du QR-code</h2>
              <div className="qr-reader__data">
                <div className="qr-reader__data-row">
                  <span className="qr-reader__label">Fournisseur</span>
                  <span className="qr-reader__value">{parsedData.companyName}</span>
                </div>
                <div className="qr-reader__data-row">
                  <span className="qr-reader__label">Adresse</span>
                  <span className="qr-reader__value">
                    {parsedData.street} {parsedData.buildingNumber}, {parsedData.postalCode} {parsedData.city}
                  </span>
                </div>
                <div className="qr-reader__data-row">
                  <span className="qr-reader__label">Montant</span>
                  <span className="qr-reader__value qr-reader__value--amount">
                    {formatAmount(parsedData.amount, parsedData.currency)}
                  </span>
                </div>
                <div className="qr-reader__data-row">
                  <span className="qr-reader__label">Référence</span>
                  <span className="qr-reader__value qr-reader__value--mono">
                    {parsedData.payment_reference}
                  </span>
                </div>
              </div>
            </section>

            {/* Section informations complémentaires avec champ Mandat */}
            <section className="qr-reader__section">
              <h2>Informations complémentaires</h2>
              <div className="qr-reader__form-group">
                <label htmlFor="mandat" className="qr-reader__form-label">
                  Mandat
                </label>
                <input
                  type="text"
                  id="mandat"
                  value={mandat}
                  onChange={(e) => setMandat(e.target.value)}
                  placeholder="Code client fournisseur (optionnel)"
                  maxLength={20}
                  className="qr-reader__input"
                />
                <small className="qr-reader__help-text">
                  Optionnel - Correspond au numéro de client chez le fournisseur (ex: "764", "M001")
                </small>
              </div>
            </section>

            {/* Bouton d'envoi */}
            <section className="qr-reader__section qr-reader__section--actions">
              <button
                type="submit"
                disabled={sending}
                className="qr-reader__submit-btn"
              >
                {sending ? 'Envoi en cours...' : 'Envoyer vers Business Central'}
              </button>
            </section>

            {/* Message de statut */}
            {sendStatus && (
              <div className={`qr-reader__status qr-reader__status--${sendStatus.success ? 'success' : 'error'}`}>
                {sendStatus.message}
              </div>
            )}
          </>
        )}
      </form>
    </div>
  )
}

export default QRReader
