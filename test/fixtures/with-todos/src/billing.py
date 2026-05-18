def refund(amount):
    # TODO: handle partial refunds
    pass


def webhook_handler():
    # FIXME: rate limit on Stripe webhook handler (saw 429s in prod)
    return "ok"


# XXX: this whole module is due for a rewrite
