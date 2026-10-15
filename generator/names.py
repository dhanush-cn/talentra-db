"""Name pools for synthetic Indian candidates.

Names are generated in several scripts and formats on purpose: the schema must store
any script with no assumption about word order (Rule 3 person name, Rule 7 UTF-8).

Formats produced:
  * "Given Family"             Priya Sharma
  * "Initials Given"           C N Dhanush        (common in Karnataka and Tamil Nadu)
  * single name                Ranganath
  * native script              ಮಂಜುನಾಥ್ ಗೌಡ, राहुल शर्मा, முருகன், శ్రీనివాస్ రెడ్డి

Each native-script name carries a Latin transliteration used to build a plausible email.
Native-script spellings are drafts; a native speaker should review them before submission.
"""

LATIN_GIVEN = [
    "Aarav", "Aditi", "Akash", "Ananya", "Arjun", "Bhavana", "Bhargav", "Chetan", "Deepa", "Dhanush",
    "Divya", "Farhan", "Ganesh", "Gurpreet", "Harish", "Harpreet", "Imran", "Joseph", "Kavya", "Kiran",
    "Lakshmi", "Lalremruati", "Manjunath", "Mary", "Meera", "Mohan", "Nandini", "Naveen", "Pooja", "Prakash",
    "Priya", "Rahul", "Rakesh", "Ramesh", "Ranganath", "Revathi", "Sanjay", "Shreya", "Sneha", "Srinivas",
    "Suresh", "Swathi", "Tenzin", "Varun", "Vidya", "Vijay", "Vinay", "Yashas", "Zoya", "Ayesha",
]

LATIN_FAMILY = [
    "Rao", "Reddy", "Sharma", "Verma", "Iyer", "Nair", "Gowda", "Hegde", "Kulkarni", "Patil",
    "Desai", "Joshi", "Menon", "Pillai", "Shetty", "Naidu", "Khan", "Singh", "Das", "Mukherjee",
    "Banerjee", "Chatterjee", "D'Souza", "Fernandes", "Gupta", "Agarwal", "Mehta", "Shah", "Kumar", "Yadav",
]

# (native given, latin given) and (native family, latin family) per script.
NATIVE = {
    "kn": {
        "given": [("ರವಿ", "ravi"), ("ಸುರೇಶ್", "suresh"), ("ಮಂಜುನಾಥ್", "manjunath"), ("ಲಕ್ಷ್ಮಿ", "lakshmi"),
                  ("ಕಾವ್ಯ", "kavya"), ("ಗಣೇಶ್", "ganesh"), ("ಪ್ರಿಯಾ", "priya"), ("ನವೀನ್", "naveen"),
                  ("ರಂಗನಾಥ್", "ranganath"), ("ಧನುಷ್", "dhanush")],
        "family": [("ಗೌಡ", "gowda"), ("ರಾವ್", "rao"), ("ಹೆಗಡೆ", "hegde"), ("ಶೆಟ್ಟಿ", "shetty")],
    },
    "hi": {
        "given": [("राहुल", "rahul"), ("प्रिया", "priya"), ("अमित", "amit"), ("सुनीता", "sunita"),
                  ("विजय", "vijay"), ("पूजा", "pooja"), ("संजय", "sanjay"), ("नेहा", "neha")],
        "family": [("शर्मा", "sharma"), ("वर्मा", "verma"), ("गुप्ता", "gupta"), ("सिंह", "singh"), ("यादव", "yadav")],
    },
    "ta": {
        "given": [("முருகன்", "murugan"), ("லட்சுமி", "lakshmi"), ("கார்த்திக்", "karthik"),
                  ("பிரியா", "priya"), ("செல்வம்", "selvam")],
        "family": [],          # Tamil names are often a single given name with an initial
    },
    "te": {
        "given": [("శ్రీనివాస్", "srinivas"), ("లక్ష్మి", "lakshmi"), ("రవి", "ravi"), ("సాయి", "sai")],
        "family": [("రెడ్డి", "reddy"), ("నాయుడు", "naidu")],
    },
}

# Share of candidates per name style; must sum to 1.
NAME_STYLE_WEIGHTS = {
    "latin_full": 0.70,
    "latin_initials": 0.08,
    "latin_single": 0.07,
    "kn": 0.05,
    "hi": 0.05,
    "ta": 0.03,
    "te": 0.02,
}

EMAIL_DOMAINS = ["gmail.com", "yahoo.co.in", "outlook.com", "rediffmail.com", "hotmail.com"]


def make_name(rng):
    """Returns (display_name, latin_base_for_email)."""
    style = rng.choices(list(NAME_STYLE_WEIGHTS), weights=NAME_STYLE_WEIGHTS.values())[0]
    if style == "latin_full":
        given, family = rng.choice(LATIN_GIVEN), rng.choice(LATIN_FAMILY)
        return f"{given} {family}", f"{given}.{family}"
    if style == "latin_initials":
        given = rng.choice(LATIN_GIVEN)
        initials = " ".join(rng.sample("ABCDGHKMNPRSTV", rng.randint(1, 2)))
        return f"{initials} {given}", given
    if style == "latin_single":
        given = rng.choice(LATIN_GIVEN)
        return given, given
    pool = NATIVE[style]
    given, given_latin = rng.choice(pool["given"])
    if pool["family"] and rng.random() < 0.8:
        family, family_latin = rng.choice(pool["family"])
        return f"{given} {family}", f"{given_latin}.{family_latin}"
    return given, given_latin


def name_variant(rng, name):
    """A near-duplicate spelling of the same person (for the duplicate-detection test data)."""
    variants = [
        name.upper(),
        name.replace(" ", "  "),
        " ".join(reversed(name.split())) if " " in name else name + " ",
        name.split()[0] if " " in name else name,
    ]
    return rng.choice(variants).strip() or name
