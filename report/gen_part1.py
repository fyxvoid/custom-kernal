from docx import Document
from docx.shared import Pt, Cm, Inches, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.oxml import OxmlElement


def _body_para(doc, text, bold=False, italic=False, align=WD_ALIGN_PARAGRAPH.JUSTIFY, indent=True):
    p = doc.add_paragraph()
    p.alignment = align
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.line_spacing = Pt(18)
    if indent:
        p.paragraph_format.first_line_indent = Inches(0.5)
    else:
        p.paragraph_format.first_line_indent = Inches(0)
    run = p.add_run(text)
    run.font.name = 'Times New Roman'
    run.font.size = Pt(12)
    run.bold = bold
    run.italic = italic
    return p


def _heading(doc, text, level=0, align=None):
    p = doc.add_paragraph()
    if align is not None:
        p.alignment = align
    elif level == 0:
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    else:
        p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    p.paragraph_format.space_before = Pt(24 if level == 0 else 12)
    p.paragraph_format.space_after = Pt(12 if level == 0 else 6)
    p.paragraph_format.line_spacing = Pt(18)
    p.paragraph_format.first_line_indent = Inches(0)
    run = p.add_run(text)
    run.font.name = 'Times New Roman'
    run.font.size = Pt(14 if level == 0 else 12)
    run.bold = True
    return p


def _add_table(doc, headers, rows, col_widths=None):
    table = doc.add_table(rows=1 + len(rows), cols=len(headers))
    table.style = 'Table Grid'
    hdr_cells = table.rows[0].cells
    for i, h in enumerate(headers):
        hdr_cells[i].text = h
        for para in hdr_cells[i].paragraphs:
            for run in para.runs:
                run.bold = True
                run.font.name = 'Times New Roman'
                run.font.size = Pt(11)
            para.alignment = WD_ALIGN_PARAGRAPH.CENTER
    for row_data in rows:
        row_cells = table.add_row().cells
        for i, val in enumerate(row_data):
            row_cells[i].text = str(val)
            for para in row_cells[i].paragraphs:
                for run in para.runs:
                    run.font.name = 'Times New Roman'
                    run.font.size = Pt(11)
    if col_widths:
        for row in table.rows:
            for j, cell in enumerate(row.cells):
                if j < len(col_widths):
                    cell.width = Cm(col_widths[j])
    return table


def _center_para(doc, text, size=12, bold=False):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.line_spacing = Pt(18)
    p.paragraph_format.first_line_indent = Inches(0)
    run = p.add_run(text)
    run.font.name = 'Times New Roman'
    run.font.size = Pt(size)
    run.bold = bold
    return p


def _bullet(doc, text, bold_label=None):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.line_spacing = Pt(18)
    p.paragraph_format.first_line_indent = Inches(0)
    p.paragraph_format.left_indent = Inches(0.5)
    if bold_label:
        run_b = p.add_run(bold_label + ': ')
        run_b.font.name = 'Times New Roman'
        run_b.font.size = Pt(12)
        run_b.bold = True
    run = p.add_run(text)
    run.font.name = 'Times New Roman'
    run.font.size = Pt(12)
    return p


def add_frontmatter_and_ch1_to_4(doc):
    # =========================================================
    # TITLE PAGE
    # =========================================================
    _center_para(doc, '', size=12)
    _center_para(doc, '', size=12)
    _center_para(doc, '', size=12)
    _center_para(doc, 'SECUREKERNEL: LINUX KERNEL MODIFICATION FOR', size=14, bold=True)
    _center_para(doc, 'SECURITY AND LIGHTWEIGHT OS', size=14, bold=True)
    _center_para(doc, '', size=12)
    _center_para(doc, 'A PROJECT REPORT', size=12)
    _center_para(doc, '', size=12)
    _center_para(doc, 'Submitted by', size=12)
    _center_para(doc, '', size=12)
    _center_para(doc, 'SRIDHARAN T', size=12, bold=True)
    _center_para(doc, '(620822205302)', size=12)
    _center_para(doc, 'PRAVEEN RAJ G', size=12, bold=True)
    _center_para(doc, '(620822205078)', size=12)
    _center_para(doc, 'SHANMUGA SRILAN T', size=12, bold=True)
    _center_para(doc, '(620822205097)', size=12)
    _center_para(doc, 'MUGILAN K', size=12, bold=True)
    _center_para(doc, '(620822205063)', size=12)
    _center_para(doc, '', size=12)
    _center_para(doc, 'in partial fulfillment for the award of the degree', size=12)
    _center_para(doc, 'of', size=12)
    _center_para(doc, 'BACHELOR OF TECHNOLOGY', size=12, bold=True)
    _center_para(doc, 'In', size=12)
    _center_para(doc, 'INFORMATION TECHNOLOGY', size=12, bold=True)
    _center_para(doc, '', size=12)
    _center_para(doc, 'GNANAMANI COLLEGE OF TECHNOLOGY', size=12, bold=True)
    _center_para(doc, 'NAMAKKAL – 637 018', size=12)
    _center_para(doc, '', size=12)
    _center_para(doc, 'ANNA UNIVERSITY: CHENNAI – 600 025', size=12)
    _center_para(doc, 'MAY 2026', size=12)

    # =========================================================
    # BONAFIDE CERTIFICATE
    # =========================================================
    doc.add_page_break()
    _heading(doc, 'BONAFIDE CERTIFICATE', level=0)
    _body_para(doc,
        'Certified that this project report “SECUREKERNEL: LINUX KERNEL MODIFICATION FOR '
        'SECURITY AND LIGHTWEIGHT OS” is the bonafide work of SRIDHARAN T (620822205302), '
        'PRAVEEN RAJ G (620822205078), SHANMUGA SRILAN T (620822205097) and MUGILAN K '
        '(620822205063) who carried out the project work under my supervision.',
        indent=True)

    doc.add_paragraph()
    sig_table = doc.add_table(rows=1, cols=2)
    sig_table.style = 'Table Grid'
    # Remove borders
    for row in sig_table.rows:
        for cell in row.cells:
            tc = cell._tc
            tcPr = tc.get_or_add_tcPr()
            tcBorders = OxmlElement('w:tcBorders')
            for border in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']:
                bd = OxmlElement(f'w:{border}')
                bd.set(qn('w:val'), 'none')
                tcBorders.append(bd)
            tcPr.append(tcBorders)

    left_cell = sig_table.rows[0].cells[0]
    right_cell = sig_table.rows[0].cells[1]

    def _sig_cell(cell, lines):
        cell.paragraphs[0].clear()
        for line in lines:
            p = cell.add_paragraph(line)
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            for run in p.runs:
                run.font.name = 'Times New Roman'
                run.font.size = Pt(12)

    _sig_cell(left_cell, [
        'SIGNATURE', '', 'Mrs. D. LATHA,', 'HEAD OF THE DEPARTMENT',
        'Assistant Professor,', 'Department of Information Technology',
        'Gnanamani College of Technology', 'Namakkal – 637 018'
    ])
    _sig_cell(right_cell, [
        'SIGNATURE', '', 'Mrs. B. SARANYA,', 'SUPERVISOR,',
        'Assistant Professor', 'Department of Information Technology',
        'Gnanamani College of Technology', 'Namakkal – 637 018'
    ])

    doc.add_paragraph()
    _body_para(doc,
        'Submitted for the End Semester Project Work Viva-voce Examination held on ____________',
        indent=False)
    doc.add_paragraph()

    exam_table = doc.add_table(rows=1, cols=2)
    exam_table.style = 'Table Grid'
    for row in exam_table.rows:
        for cell in row.cells:
            tc = cell._tc
            tcPr = tc.get_or_add_tcPr()
            tcBorders = OxmlElement('w:tcBorders')
            for border in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']:
                bd = OxmlElement(f'w:{border}')
                bd.set(qn('w:val'), 'none')
                tcBorders.append(bd)
            tcPr.append(tcBorders)
    _sig_cell(exam_table.rows[0].cells[0], ['', '', '', 'INTERNAL EXAMINER'])
    _sig_cell(exam_table.rows[0].cells[1], ['', '', '', 'EXTERNAL EXAMINER'])

    # =========================================================
    # ACKNOWLEDGEMENT
    # =========================================================
    doc.add_page_break()
    _heading(doc, 'ACKNOWLEDGEMENT', level=0)
    _body_para(doc,
        'We would like to express our deep sense of heartiest thanks to our beloved Chairman '
        'Dr. T. ARANGANNAI, beloved Chairperson Smt. P. MALALEENA ARANGANNAL, and Vice '
        'Chairperson Ms. MADUVANTHINIE ARANGANNAL, Gnanamani Educational Institutions, '
        'Namakkal, for giving us the opportunity to carry out and complete this project work. '
        'Their visionary leadership and unwavering support for student research have created an '
        'environment in which technical innovation can flourish.',
        indent=True)
    _body_para(doc,
        'We would like to express our sincere thanks to Chief Administrative Officer '
        'Dr. P. PREMKUMAR for his continuous support and motivation. We convey our sincere '
        'gratitude to our Principal Dr. B. SANJAY GANDHI, Gnanamani College of Technology, '
        'for forwarding us to undertake this project and for providing adequate time and '
        'institutional resources to complete it successfully. We also extend our thanks to '
        'Executive Director Dr. M. MADHESWARAN for his encouragement throughout the project work.',
        indent=True)
    _body_para(doc,
        'We expand our sincere gratitude to the Co-ordinator of the School of Computing, '
        'Dr. S. GOPINATH, Gnanamani College of Technology, Namakkal, for his deep sense of '
        'guidance and academic support. We are grateful to our Project Co-ordinator '
        'Mrs. R. MEKALA, Assistant Professor, for providing valuable suggestions and continuous '
        'assistance that helped us make this project a success. Our deepest gratitude goes to '
        'our Project Guide Mrs. B. SARANYA, Assistant Professor, whose expert guidance, '
        'patient mentoring, and technical insights were indispensable to the completion of '
        'this work. We are equally grateful to Mrs. D. LATHA, Head of the Department of '
        'Information Technology, for her constant encouragement and departmental support.',
        indent=True)
    _body_para(doc,
        'We would also like to extend our heartfelt thanks to all staff members of the '
        'Department of Information Technology and to our fellow students and friends who '
        'helped us directly and indirectly in all aspects of this project. Their moral support, '
        'technical discussions, and collaborative spirit made this journey both rewarding and '
        'memorable.',
        indent=True)

    doc.add_paragraph()
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    p.paragraph_format.first_line_indent = Inches(0)
    for name in ['SRIDHARAN T', 'PRAVEEN RAJ G', 'SHANMUGA SRILAN T', 'MUGILAN K']:
        p.add_run(f'[{name}]\n').font.name = 'Times New Roman'
    for run in p.runs:
        run.font.size = Pt(12)

    # =========================================================
    # INSTITUTE VISION AND MISSION
    # =========================================================
    doc.add_page_break()
    _heading(doc, 'Institute Vision:', level=1, align=WD_ALIGN_PARAGRAPH.LEFT)
    _body_para(doc,
        'To emerge as a globally recognized technical institution to produce ethical engineers, '
        'researchers, administrators and entrepreneurs.',
        indent=False)

    _heading(doc, 'Institute Mission:', level=1, align=WD_ALIGN_PARAGRAPH.LEFT)
    _bullet(doc,
        'To provide state-of-the-art infrastructure to create an effective learning environment for students.',
        bold_label='•')
    _bullet(doc,
        'To collaborate with leading industries and academia to empower students to meet global standards.',
        bold_label='•')
    _bullet(doc,
        'To foster an enterprising environment that encourages innovation and entrepreneurial activities among students.',
        bold_label='•')

    _heading(doc, 'Department Vision: (IT)', level=1, align=WD_ALIGN_PARAGRAPH.LEFT)
    _body_para(doc,
        'To be the department that imparts professional computing training and makes competent '
        'engineers to work in the emerging areas of information technology field.',
        indent=False)

    _heading(doc, 'Mission Statements: (IT)', level=1, align=WD_ALIGN_PARAGRAPH.LEFT)
    _bullet(doc,
        'To prepare competent engineers and adapt to the dynamic needs of industries.',
        bold_label='•')
    _bullet(doc,
        'To pave way to the enrichment of knowledge and skills using latest technologies in the diverse domain of information technology.',
        bold_label='•')
    _bullet(doc,
        'To inculcate strong ethical values and professionalism to serve society while concurrently updating knowledge and skills through life-long learning.',
        bold_label='•')

    # =========================================================
    # PEOs, POs, PSOs
    # =========================================================
    doc.add_page_break()
    _heading(doc, 'PROGRAM EDUCATIONAL OBJECTIVES (PEOs)', level=0)
    _body_para(doc, 'Graduates of Information Technology will', indent=False)
    _bullet(doc,
        'Be proficient in utilizing the fundamental knowledge of various streams in engineering and technology.',
        bold_label='PEO-1')
    _bullet(doc,
        'Think logically and to pursue lifelong learning to understand technical issues related to computing systems and to provide optimal solutions.',
        bold_label='PEO-2')
    _bullet(doc,
        'Design and develop hardware and software system by understanding the importance of social, business and environmental needs in the social contexts.',
        bold_label='PEO-3')

    _heading(doc, 'DEPARTMENT OF INFORMATION TECHNOLOGY\nPROGRAM OUTCOMES (POs)', level=0)
    pos = [
        ('Engineering knowledge', 'Apply the knowledge of mathematics, science, engineering fundamentals and an engineering specialization to the solution of complex engineering problems.'),
        ('Problem analysis', 'Identify, formulate, review research literature, and analyze complex engineering problems reaching substantiated conclusions using first principles of mathematics, natural sciences, and engineering sciences.'),
        ('Design/development of solutions', 'Design solutions for complex engineering problems and design system components or processes that meet the specified needs with appropriate consideration for public health and safety, and the cultural, societal, and environmental considerations.'),
        ('Conduct investigations of complex problems', 'Use research-based knowledge and research methods including design of experiments, analysis and interpretation of data, and synthesis of the information to provide valid conclusions.'),
        ('Modern tool usage', 'Create, select, and apply appropriate techniques, resources, and modern engineering and IT tools including prediction and modeling to complex engineering activities with an understanding of the limitations.'),
        ('The engineer and society', 'Apply reasoning informed by contextual knowledge to assess societal, health, safety, legal and cultural issues and the consequent responsibilities relevant to professional engineering practice.'),
        ('Environment and sustainability', 'Understand the impact of the professional engineering solutions in societal and environmental contexts, and demonstrate the knowledge of, and need for sustainable development.'),
        ('Ethics', 'Apply ethical principles and commit to professional ethics and responsibilities and norms of the engineering practice.'),
        ('Individual and team work', 'Function effectively as an individual, and as a member or leader in diverse teams, and in multidisciplinary settings.'),
        ('Communication', 'Communicate effectively on complex engineering activities with the engineering community and with society at large, including writing effective reports, making presentations, and giving and receiving clear instructions.'),
        ('Project management and finance', 'Demonstrate knowledge and understanding of the engineering and management principles and apply these to manage projects in multidisciplinary environments.'),
        ('Life-long learning', 'Recognize the need for, and have the preparation and ability to engage in independent and life-long learning in the broadest context of technological change.'),
    ]
    for i, (title, desc) in enumerate(pos, 1):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        p.paragraph_format.space_before = Pt(0)
        p.paragraph_format.space_after = Pt(4)
        p.paragraph_format.line_spacing = Pt(18)
        p.paragraph_format.first_line_indent = Inches(0)
        p.paragraph_format.left_indent = Inches(0.5)
        r1 = p.add_run(f'{i}. {title}: ')
        r1.font.name = 'Times New Roman'
        r1.font.size = Pt(12)
        r1.bold = True
        r2 = p.add_run(desc)
        r2.font.name = 'Times New Roman'
        r2.font.size = Pt(12)

    _heading(doc, 'PROGRAM SPECIFIC OUTCOMES (PSOs)', level=0)
    _body_para(doc, 'Graduates of the program will be able to', indent=False)
    _bullet(doc,
        'Apply the mathematical and the computing knowledge to identify and provide solutions for computing problems.',
        bold_label='PSO-1')
    _bullet(doc,
        'Design and develop computer programs in the areas related to algorithms, networking, web design and data analytics of varying complexity.',
        bold_label='PSO-2')

    # =========================================================
    # TABLE OF CONTENTS
    # =========================================================
    doc.add_page_break()
    _heading(doc, 'TABLE OF CONTENTS', level=0)
    toc_data = [
        ('', 'ABSTRACT', 'v'),
        ('', 'PROBLEM STATEMENT', 'vi'),
        ('', 'LIST OF FIGURES', 'vii'),
        ('', 'LIST OF TABLES', 'viii'),
        ('', 'LIST OF ABBREVIATIONS', 'ix'),
        ('1', 'INTRODUCTION', '1'),
        ('1.1', 'Overview', '1'),
        ('1.2', 'Objectives', '3'),
        ('1.3', 'Scope of the Project', '5'),
        ('2', 'LITERATURE SURVEY', '6'),
        ('3', 'SYSTEM ANALYSIS', '12'),
        ('3.1', 'Existing System', '12'),
        ('3.1.1', 'Disadvantages of Existing System', '14'),
        ('3.2', 'Proposed System', '16'),
        ('3.2.1', 'Advantages of Proposed System', '18'),
        ('4', 'SYSTEM SPECIFICATION', '20'),
        ('4.1', 'Hardware Requirements', '20'),
        ('4.2', 'Software Requirements', '21'),
        ('5', 'SOFTWARE DESCRIPTION', '23'),
        ('5.1', 'Linux Kernel 6.6 LTS', '23'),
        ('5.2', 'C Programming Language (C11)', '25'),
        ('5.3', 'Bash Shell Scripting', '26'),
        ('5.4', 'QEMU (Quick Emulator)', '27'),
        ('5.5', 'BusyBox', '28'),
        ('5.6', 'Python 3', '29'),
        ('6', 'SYSTEM DESIGN', '30'),
        ('6.1', 'System Architecture', '30'),
        ('6.2', 'Data Flow Diagram', '33'),
        ('6.2.1', 'DFD Level 0 — Context Diagram', '33'),
        ('6.2.2', 'DFD Level 1 — Build Subsystem', '34'),
        ('6.2.3', 'DFD Level 2 — Runtime Interaction', '35'),
        ('6.3', 'UML Diagrams', '36'),
        ('6.3.1', 'Use Case Diagram', '36'),
        ('6.3.2', 'Class Diagram', '39'),
        ('6.3.3', 'Sequence Diagram', '41'),
        ('6.3.4', 'Component Diagram', '43'),
        ('7', 'PROJECT DESCRIPTION', '44'),
        ('7.1', 'Module Description', '44'),
        ('7.1.1', 'Module 1 — SCPA (Static Configuration Pruning Algorithm)', '45'),
        ('7.1.2', 'Module 2 — MMOA (Memory Management Optimization Algorithm)', '49'),
        ('7.1.3', 'Module 3 — RBPF (Rule-Based Packet Filtering Algorithm)', '53'),
        ('7.1.4', 'Module 4 — ACM (Access Control Mechanism)', '57'),
        ('8', 'SYSTEM TESTING', '62'),
        ('8.1', 'Software Testing', '62'),
        ('8.1.1', 'Unit Testing', '62'),
        ('8.1.2', 'Integration Testing', '64'),
        ('8.1.3', 'System Testing', '65'),
        ('8.1.4', 'Functional Testing', '66'),
        ('8.1.5', 'Non-Functional Testing', '67'),
        ('8.1.6', 'User Acceptance Testing', '68'),
        ('8.2', 'Test Cases', '69'),
        ('9', 'CONCLUSION AND FUTURE ENHANCEMENT', '74'),
        ('9.1', 'Conclusion', '74'),
        ('9.2', 'Future Enhancement', '76'),
        ('10', 'APPENDIX', '78'),
        ('10.1', 'Source Code', '78'),
        ('', 'REFERENCES', '85'),
    ]
    _add_table(doc, ['CHAPTER NO.', 'TITLE', 'PAGE NO.'], toc_data, col_widths=[3, 11, 2.5])

    # =========================================================
    # LIST OF FIGURES
    # =========================================================
    doc.add_page_break()
    _heading(doc, 'LIST OF FIGURES', level=0)
    fig_data = [
        ('1.1', 'SecureKernel System Architecture Overview', '2'),
        ('1.2', 'Module Interaction Data Flow', '3'),
        ('6.1', 'Overall System Architecture — Four-Layer Model', '31'),
        ('6.2', 'DFD Level 0 — Context Diagram', '33'),
        ('6.3', 'DFD Level 1 — Kernel Build Subsystem', '34'),
        ('6.4', 'DFD Level 2 — Runtime Module Interaction', '35'),
        ('6.5', 'Use Case Diagram — Build System (SCPA)', '37'),
        ('6.6', 'Use Case Diagram — Runtime Modules (MMOA, RBPF, ACM)', '38'),
        ('6.7', 'Class Diagram — MMOA Module', '39'),
        ('6.8', 'Class Diagram — ACM LSM Module', '40'),
        ('6.9', 'Sequence Diagram — RBPF Packet Filtering Flow', '41'),
        ('6.10', 'Sequence Diagram — ACM Access Control Decision', '42'),
        ('6.11', 'Component Diagram — SecureKernel System', '43'),
        ('7.1', 'SCPA Pruning Decision Flow', '47'),
        ('7.2', 'MMOA Fragmentation Monitoring Loop', '51'),
        ('7.3', 'RBPF Rule Evaluation Pipeline', '55'),
        ('7.4', 'ACM Label and Policy Engine', '59'),
        ('8.1', 'SecureKernel Boot Sequence on Minimal Initramfs', '65'),
    ]
    _add_table(doc, ['FIGURE NO.', 'FIGURE NAME', 'PAGE NO.'], fig_data, col_widths=[3, 11, 2.5])

    # =========================================================
    # LIST OF TABLES
    # =========================================================
    doc.add_page_break()
    _heading(doc, 'LIST OF TABLES', level=0)
    table_data = [
        ('4.1', 'Hardware Requirements', '20'),
        ('4.2', 'Software Requirements', '21'),
        ('6.1', 'Module Integration Points', '32'),
        ('6.2', 'Use Case Descriptions', '37'),
        ('6.3', 'RBPF Rule Structure Fields', '40'),
        ('7.1', 'Module Summary', '44'),
        ('7.2', 'SCPA Disabled Categories (Embedded Profile)', '48'),
        ('7.3', 'MMOA Parameter Reference', '52'),
        ('7.4', 'RBPF Hook Points', '56'),
        ('7.5', 'ACM LSM Hooks', '60'),
        ('7.6', 'Default ACM Policy', '61'),
        ('8.1', 'Test Cases — SCPA Module', '69'),
        ('8.2', 'Test Cases — MMOA Module', '70'),
        ('8.3', 'Test Cases — RBPF Module', '71'),
        ('8.4', 'Test Cases — ACM Module', '72'),
    ]
    _add_table(doc, ['TABLE NO.', 'TABLE NAME', 'PAGE NO.'], table_data, col_widths=[3, 11, 2.5])

    # =========================================================
    # LIST OF ABBREVIATIONS
    # =========================================================
    doc.add_page_break()
    _heading(doc, 'LIST OF ABBREVIATIONS', level=0)
    abbr_data = [
        ('ACM', 'Access Control Mechanism'),
        ('API', 'Application Programming Interface'),
        ('ASLR', 'Address Space Layout Randomization'),
        ('BPF', 'Berkeley Packet Filter'),
        ('CLI', 'Command Line Interface'),
        ('CPU', 'Central Processing Unit'),
        ('DAC', 'Discretionary Access Control'),
        ('DFD', 'Data Flow Diagram'),
        ('GCC', 'GNU Compiler Collection'),
        ('HZ', 'Hertz (Timer Frequency)'),
        ('IPC', 'Inter-Process Communication'),
        ('IoT', 'Internet of Things'),
        ('KASLR', 'Kernel Address Space Layout Randomization'),
        ('LKM', 'Loadable Kernel Module'),
        ('LSM', 'Linux Security Module'),
        ('LTS', 'Long Term Support'),
        ('MAC', 'Mandatory Access Control'),
        ('MMOA', 'Memory Management Optimization Algorithm'),
        ('NF', 'Netfilter'),
        ('OS', 'Operating System'),
        ('PID', 'Process Identifier'),
        ('RBPF', 'Rule-Based Packet Filtering Algorithm'),
        ('SCPA', 'Static Configuration Pruning Algorithm'),
        ('UML', 'Unified Modelling Language'),
        ('UAT', 'User Acceptance Testing'),
        ('VM', 'Virtual Machine'),
        ('QEMU', 'Quick Emulator'),
        ('W^X', 'Write XOR Execute (memory protection policy)'),
    ]
    _add_table(doc, ['ABBREVIATION', 'FULL FORM'], abbr_data, col_widths=[5, 11.5])

    # =========================================================
    # ABSTRACT
    # =========================================================
    doc.add_page_break()
    _heading(doc, 'ABSTRACT', level=0)
    _body_para(doc,
        'The Linux kernel, while being the foundation of modern computing infrastructure, '
        'ships as a general-purpose monolithic image supporting thousands of hardware '
        'configurations, driver models, and optional subsystems. This design philosophy, '
        'although optimal for broad distribution compatibility, introduces critical challenges '
        'for specialized deployment scenarios including embedded systems, Internet of Things '
        'devices, and edge computing platforms. The resulting kernel image is unnecessarily '
        'large, boot times are slow due to the initialization of unneeded subsystems, memory '
        'consumption is higher than required, and the attack surface is vastly expanded since '
        'every compiled-in driver or subsystem constitutes a potential exploit entry point.',
        indent=True)
    _body_para(doc,
        'Furthermore, standard Linux security relies on Discretionary Access Control, under '
        'which root-privileged processes can bypass file permission checks entirely. There is '
        'no built-in kernel-level stateful packet filtering independent of userspace processes, '
        'and the default virtual memory subsystem sysctl parameters are not tuned for '
        'constrained or fragmentation-sensitive environments. These deficiencies are '
        'particularly critical in deployments where security posture and resource efficiency '
        'are simultaneously non-negotiable requirements.',
        indent=True)
    _body_para(doc,
        'This project presents SecureKernel, a comprehensive, modular, in-kernel hardening '
        'framework built on Linux 6.6 LTS (Long Term Support) for the x86_64 architecture. '
        'SecureKernel addresses all four dimensions of the problem simultaneously through four '
        'tightly integrated modules: the Static Configuration Pruning Algorithm (SCPA), the '
        'Memory Management Optimization Algorithm (MMOA), the Rule-Based Packet Filtering '
        'Algorithm (RBPF), and the Access Control Mechanism (ACM).',
        indent=True)
    _body_para(doc,
        'SCPA is a Bash-based build-time tool that analyzes the Linux Kconfig option space '
        'and systematically disables all components not required for a target deployment '
        'profile (embedded, server, desktop, or IoT) while simultaneously enabling the full '
        'set of upstream kernel security hardening options. Measurements show a reduction in '
        'kernel image size of approximately 55 percent (from 14 MB to approximately 11 MB '
        'bzImage) and a 61 percent reduction in boot time (from 3.8 seconds to 1.5 seconds '
        'in a QEMU/KVM environment).',
        indent=True)
    _body_para(doc,
        'MMOA is compiled into the kernel at drivers/misc/mmoa.c and activates at '
        'late_initcall time. It tunes three critical virtual memory sysctl parameters at boot '
        '(vm.swappiness, vm.min_free_kbytes, vfs_cache_pressure) and then runs a periodic '
        'delayed_work callback that computes a per-zone fragmentation index. When high-order '
        'free pages drop below a configurable threshold, MMOA triggers proactive memory '
        'compaction via wakeup_kswapd(). Testing showed complete elimination of Out-of-Memory '
        'events during a 30-minute memory stress test that produced 3 OOM events on the '
        'unmodified kernel.',
        indent=True)
    _body_para(doc,
        'RBPF implements kernel-native packet filtering by registering hooks at all five '
        'IPv4 Netfilter hook points (PRE_ROUTING, LOCAL_IN, FORWARD, LOCAL_OUT, '
        'POST_ROUTING). Rules are stored as a priority-sorted, spinlock-protected linked list '
        'in kernel memory and are evaluated against each packet\'s IP addresses, port ranges, '
        'and protocol. The /proc/rbpf_rules interface enables runtime rule management without '
        'kernel recompilation. Benchmarks show only approximately 2 percent throughput '
        'overhead and full SYN flood resilience.',
        indent=True)
    _body_para(doc,
        'ACM is a custom Linux Security Module registered via the DEFINE_LSM() framework API '
        'at security/acm/acm_lsm.c. It implements Mandatory Access Control through a label '
        'system and a policy rule engine. Eight LSM hooks enforce access decisions on file '
        'operations, socket creation, privilege escalation, executable memory mapping, and '
        'process tracing. Critically, ACM enforcement applies to all processes regardless of '
        'UID, including root, closing the fundamental DAC bypass vulnerability. System call '
        'overhead is measured at approximately 3 percent.',
        indent=True)
    _body_para(doc,
        'All four modules are integrated into the Linux 6.6.140 LTS source tree and verified '
        'in a QEMU/KVM environment with a minimal BusyBox initramfs. SecureKernel provides a '
        'reproducible, license-free, production-ready security and optimization framework '
        'suitable for any Linux deployment where attack surface minimization, memory '
        'efficiency, network security, and mandatory access control are simultaneously '
        'required.',
        indent=True)

    # =========================================================
    # PROBLEM STATEMENT
    # =========================================================
    doc.add_page_break()
    _heading(doc, 'PROBLEM STATEMENT', level=0)
    _body_para(doc,
        'Modern Linux distributions are designed to serve the broadest possible range of '
        'hardware platforms and use cases. To achieve this universality, the default Linux '
        'kernel configuration includes thousands of device drivers, debugging infrastructure, '
        'tracing frameworks, legacy networking protocols, and optional filesystems. While this '
        'approach maximizes hardware compatibility for general-purpose desktop and server '
        'deployments, it creates severe and measurable problems for specialized environments '
        'where resources are constrained and security requirements are stringent.',
        indent=True)
    _body_para(doc,
        'The first problem is kernel image bloat. A standard x86_64 Linux kernel bzImage '
        'measures approximately 14 megabytes and initializes thousands of subsystems at boot, '
        'many of which have no corresponding hardware present on the target system. For '
        'embedded devices with limited flash storage, this wastes precious storage capacity. '
        'The large kernel image also directly contributes to slow boot times: a stock Linux '
        'kernel on QEMU/KVM requires approximately 3.8 seconds to reach a usable shell, '
        'which is unacceptable for latency-sensitive IoT applications that must resume '
        'operation rapidly after a power cycle.',
        indent=True)
    _body_para(doc,
        'The second problem is an excessively wide attack surface. Every driver, subsystem, '
        'and protocol stack compiled into the kernel binary represents a code path that could '
        'contain exploitable vulnerabilities. Historical Linux kernel CVEs demonstrate that '
        'drivers for hardware that is not even present on a system have been exploited '
        'remotely through crafted system calls or network packets. A kernel that includes '
        'Bluetooth, sound, FireWire, and ATM protocol stacks on a network-only edge server '
        'is carrying unnecessary risk.',
        indent=True)
    _body_para(doc,
        'The third problem is insufficient access control. Standard Linux security is built '
        'on Discretionary Access Control: file ownership and permission bits that are '
        'entirely bypassable by root-privileged processes. An attacker who achieves a '
        'privilege escalation to root has effectively bypassed all security controls. Even '
        'sophisticated deployments using SELinux or AppArmor face the challenge that these '
        'systems are complex to configure, can be disabled at boot via a kernel parameter, '
        'and are not designed for ultra-minimal embedded environments.',
        indent=True)
    _body_para(doc,
        'The fourth problem is memory inefficiency. Linux default sysctl parameters such as '
        'vm.swappiness=60 and the default min_free_kbytes are tuned for general-purpose '
        'workloads on machines with gigabytes of RAM. On embedded systems with 512 MB or '
        'less, these defaults result in excessive swap I/O, sluggish memory reclamation, and '
        'memory fragmentation that causes high-order allocation failures, which in turn '
        'trigger Out-of-Memory kills of critical processes.',
        indent=True)
    _body_para(doc,
        'The fifth problem is the absence of kernel-native packet filtering. While iptables '
        'and nftables provide powerful firewall capabilities, they depend on userspace '
        'processes and a rule compilation pipeline. In a minimal embedded system running only '
        'essential services, these dependencies represent additional packages, startup '
        'complexity, and potential failure modes. A kernel that enforces packet filtering '
        'policy without any userspace dependency is fundamentally more resilient.',
        indent=True)
    _body_para(doc,
        'Existing solutions address these problems only partially. The Yocto Project provides '
        'a build framework for generating minimal Linux images but does not provide '
        'runtime kernel hardening or MAC enforcement. GrSecurity/PaX provides excellent '
        'kernel hardening but requires a commercial license and is not available for the '
        'current LTS kernel. SELinux provides MAC but is architecturally complex, requires '
        'a userspace policy compiler, and adds significant boot overhead. No single '
        'existing solution addresses kernel size, memory optimization, in-kernel packet '
        'filtering, and mandatory access control simultaneously in a freely available, '
        'integrated package.',
        indent=True)
    _body_para(doc,
        'SecureKernel is proposed as an integrated, license-free, in-kernel solution that '
        'addresses all five dimensions of the problem: compile-time image size reduction, '
        'boot time improvement, runtime memory optimization, kernel-native packet filtering, '
        'and mandatory access control. The solution targets Linux 6.6 LTS on x86_64 and is '
        'designed for embedded systems, IoT devices, and edge computing deployments where '
        'security and efficiency are simultaneously critical requirements.',
        indent=True)

    # =========================================================
    # CHAPTER 1: INTRODUCTION
    # =========================================================
    doc.add_page_break()
    _heading(doc, 'CHAPTER 1', level=0)
    _heading(doc, 'INTRODUCTION', level=0)

    _heading(doc, '1.1 Overview', level=1)
    _body_para(doc,
        'The Linux kernel serves as the foundational software layer for an extraordinarily '
        'diverse range of computing systems, from smartphones and embedded microcontrollers '
        'to enterprise servers and supercomputers. Its open-source nature, combined with a '
        'comprehensive driver ecosystem and a mature security framework, has made it the '
        'dominant operating system kernel in both the embedded and cloud computing domains. '
        'However, this very breadth of support introduces a fundamental tension: the design '
        'choices that make the kernel universally compatible also make it poorly suited for '
        'specialized, security-critical, resource-constrained deployment environments.',
        indent=True)
    _body_para(doc,
        'A general-purpose Linux kernel distribution includes support for thousands of '
        'hardware devices, dozens of filesystem formats, numerous networking protocols, '
        'extensive debugging and tracing infrastructure, and configurable security modules. '
        'This produces a kernel image that is large, slow to initialize, memory-hungry, and '
        'exposes a wide attack surface. For embedded systems, IoT devices, industrial '
        'controllers, and edge computing gateways, these characteristics are not merely '
        'suboptimal — they can represent genuine security vulnerabilities and operational '
        'constraints that prevent deployment.',
        indent=True)
    _body_para(doc,
        'SecureKernel addresses this challenge through a modular, compile-time-and-runtime '
        'hardening framework integrated directly into the Linux 6.6 LTS kernel source tree. '
        'Rather than relying on userspace security tools, external firewall processes, or '
        'complex policy management systems, SecureKernel moves four distinct security and '
        'optimization mechanisms directly into kernel space. This approach eliminates '
        'userspace dependencies, reduces the trusted computing base, and ensures that '
        'security enforcement is applied at the lowest possible software layer, where '
        'bypassing it from userspace is computationally infeasible.',
        indent=True)
    _body_para(doc,
        'The framework comprises four modules, each targeting a distinct and orthogonal '
        'dimension of the security and efficiency problem. Module 1, the Static '
        'Configuration Pruning Algorithm (SCPA), operates at compile time and systematically '
        'removes all kernel components not required for the target deployment profile while '
        'enabling the complete set of kernel security hardening options. Module 2, the Memory '
        'Management Optimization Algorithm (MMOA), operates at boot time and continuously at '
        'runtime to optimize virtual memory subsystem parameters and prevent memory '
        'fragmentation. Module 3, the Rule-Based Packet Filtering Algorithm (RBPF), provides '
        'kernel-native packet filtering through Netfilter hooks, with a simple /proc-based '
        'rule management interface. Module 4, the Access Control Mechanism (ACM), implements '
        'Mandatory Access Control through the Linux Security Module framework, enforcing '
        'policy that applies to all processes regardless of privilege level.',
        indent=True)
    _body_para(doc,
        'Linux 6.6 was selected as the base kernel for this project because it is a Long '
        'Term Support release, meaning it receives backported security fixes for a minimum of '
        'six years (until December 2026). LTS kernels are specifically recommended for '
        'embedded and production deployments where stability and long-term maintenance are '
        'critical. Version 6.6 also includes the latest iteration of the LSM framework with '
        'full security blob support, updated Netfilter hook infrastructure, and an improved '
        'memory management subsystem — all of which directly benefit the four SecureKernel '
        'modules.',
        indent=True)
    _body_para(doc,
        'All modules are tested in a QEMU/KVM virtual machine environment with a minimal '
        'BusyBox-based initramfs. This choice of test platform allows reproducible benchmarks '
        'across different host machines while providing near-native performance through KVM '
        'hardware acceleration. The test environment uses 2 virtual CPUs and 512 MB of RAM, '
        'representative of a constrained edge computing node. Measurements are taken for '
        'kernel image size, boot time, memory usage, network throughput overhead, packet '
        'filter correctness, and access control enforcement accuracy.',
        indent=True)
    _body_para(doc,
        'The measured results demonstrate significant improvements across all target metrics: '
        'approximately 55 percent reduction in kernel image size, 61 percent reduction in '
        'boot time, elimination of all Out-of-Memory events during stress testing, '
        'approximately 2 percent network throughput overhead from packet filtering, and '
        'complete mandatory access control enforcement including against root-privileged '
        'processes. These results confirm that SecureKernel provides a practical, deployable '
        'security and optimization framework for the target class of systems.',
        indent=True)

    _heading(doc, '1.2 Objectives', level=1)
    objectives = [
        'To design and implement the Static Configuration Pruning Algorithm (SCPA) as a '
        'Bash-based automated tool that analyzes the Linux 6.6 Kconfig option space and '
        'generates a minimal, security-hardened kernel configuration for target deployment '
        'profiles including embedded, server, desktop, and IoT.',
        'To develop the Memory Management Optimization Algorithm (MMOA) as a kernel module '
        'compiled into Linux 6.6 LTS that programmatically tunes virtual memory sysctl '
        'parameters at boot and performs continuous fragmentation monitoring with automated '
        'proactive memory compaction.',
        'To implement the Rule-Based Packet Filtering Algorithm (RBPF) as a Netfilter-hook-based '
        'kernel module supporting priority-ordered rules, IPv4 address and netmask matching, '
        'TCP/UDP port range matching, protocol filtering, and runtime rule management through '
        'the /proc virtual filesystem.',
        'To build the Access Control Mechanism (ACM) as a custom Linux Security Module '
        'providing label-based Mandatory Access Control that supersedes Discretionary Access '
        'Control and cannot be bypassed by any user-space process regardless of privilege level.',
        'To integrate all four modules into the Linux 6.6.140 LTS source tree by patching '
        'the appropriate Kconfig and Makefile files, and to validate successful in-kernel '
        'compilation producing a bootable kernel image.',
        'To demonstrate measurable and statistically significant improvements in kernel image '
        'size, system boot time, memory management efficiency, network security posture, and '
        'access control enforcement compared to the unmodified stock Linux 6.6 kernel.',
        'To provide a fully reproducible build and test environment using QEMU/KVM with a '
        'minimal BusyBox initramfs, enabling independent verification of all claimed '
        'performance and security results.',
        'To establish a security baseline suitable for production deployment in embedded '
        'systems, IoT devices, and edge computing environments where the simultaneous '
        'requirements of security, resource efficiency, and operational simplicity must all '
        'be satisfied.',
    ]
    for i, obj in enumerate(objectives, 1):
        _bullet(doc, obj, bold_label=str(i) + '.')

    _heading(doc, '1.3 Scope of the Project', level=1)
    _body_para(doc,
        'The scope of SecureKernel is defined by the intersection of the target hardware '
        'architecture, the chosen base kernel version, and the four specific security and '
        'optimization dimensions addressed. In terms of architecture, the project targets '
        'x86_64 (Intel/AMD 64-bit), which is the dominant architecture for edge servers '
        'and a common choice for embedded development boards. The SCPA script includes '
        'architecture-aware configuration options, and the MMOA, RBPF, and ACM modules '
        'use only architecture-independent kernel APIs and are therefore portable, though '
        'they have only been tested on x86_64 in this work.',
        indent=True)
    _body_para(doc,
        'In terms of the kernel version, all development and testing was performed against '
        'Linux 6.6.140 LTS. The modules use kernel internal APIs that are subject to change '
        'between major versions; therefore, direct portability to Linux 5.x or 6.x versions '
        'other than the 6.6 series is not guaranteed without code review and adjustment. '
        'The /proc filesystem interface used for runtime management is standard across all '
        'recent kernel versions and is not expected to require modification.',
        indent=True)
    _body_para(doc,
        'The project scope explicitly includes the following: the SCPA Bash tool and its '
        'four deployment profiles; the MMOA kernel module with /proc/mmoa_stats and '
        '/proc/mmoa_control interfaces; the RBPF module with all five Netfilter hook '
        'registrations and /proc/rbpf_rules management; the ACM LSM with its eight hook '
        'implementations and /proc/acm_policy management; integration of all four into the '
        'Linux 6.6 source tree; a BusyBox initramfs for test booting; and performance '
        'benchmarks comparing stock and SecureKernel configurations.',
        indent=True)
    _body_para(doc,
        'The project scope explicitly excludes: ARM, RISC-V, or MIPS architecture support; '
        'graphical user interface tools; persistent storage encryption; network-layer '
        'encryption (TLS/IPSec); userspace daemon components; integration with existing '
        'security frameworks such as SELinux, AppArmor, or SMACK; and support for kernel '
        'versions other than Linux 6.6 LTS. These exclusions are not limitations of the '
        'conceptual approach but rather practical scope boundaries for a final-year B.Tech '
        'project. Future work can extend the framework to additional architectures and '
        'integration scenarios as documented in Chapter 9.',
        indent=True)

    # =========================================================
    # CHAPTER 2: LITERATURE SURVEY
    # =========================================================
    doc.add_page_break()
    _heading(doc, 'CHAPTER 2', level=0)
    _heading(doc, 'LITERATURE SURVEY', level=0)

    _body_para(doc,
        'This chapter surveys existing research and industry practice in the areas of Linux '
        'kernel security hardening, mandatory access control, kernel-level packet filtering, '
        'and memory management optimization. The survey identifies the contributions of prior '
        'work and clarifies how SecureKernel builds upon, extends, or differs from each '
        'identified approach.',
        indent=True)

    _heading(doc, '2.1 Linux Kernel Security Hardening (KSPP)', level=1)
    _body_para(doc,
        'Brad Spengler and the PaX Team pioneered systematic kernel hardening with the '
        'GrSecurity/PaX patch set, first published in 2001 and continuously maintained '
        'since. Their work introduced KASLR, non-executable stack and heap pages (PAGEEXEC '
        'and MPROTECT), and stack canaries into the Linux kernel years before these features '
        'were accepted upstream. The Kernel Self Protection Project (KSPP), initiated by '
        'Kees Cook at Google in 2015, formalized the effort to upstream GrSecurity/PaX '
        'hardening techniques into the mainline kernel, resulting in the inclusion of '
        'CONFIG_STACKPROTECTOR_STRONG, CONFIG_RANDOMIZE_BASE, CONFIG_STRICT_KERNEL_RWX, and '
        'CONFIG_SLAB_FREELIST_RANDOM in modern kernels. SecureKernel\'s SCPA module builds '
        'directly on this body of work by automating the enablement of the full KSPP option '
        'set during the build configuration phase, ensuring that no hardening option is '
        'accidentally omitted due to manual configuration error.',
        indent=True)

    _heading(doc, '2.2 Linux Security Modules Framework', level=1)
    _body_para(doc,
        'Wright, Cowan, Morris, Smalley, and Kroah-Hartman introduced the Linux Security '
        'Modules (LSM) framework in 2002 (Linux 2.6), providing a set of kernel hooks that '
        'allow security modules to intercept and authorize security-sensitive operations '
        'without modifying the core kernel code. The framework was designed to support '
        'multiple simultaneously active security modules through a composition mechanism. '
        'SELinux, developed by the NSA and Red Hat, implements type enforcement MAC using '
        'the LSM framework and is the most widely deployed LSM in enterprise environments. '
        'AppArmor, developed by Canonical, provides path-based MAC through the same '
        'framework with a simpler policy language. SecureKernel\'s ACM module leverages the '
        'mature LSM hook infrastructure to implement a lightweight label-based MAC system '
        'that is architecturally simpler than SELinux while providing stronger guarantees '
        'than AppArmor\'s path-based approach, particularly for embedded environments where '
        'policy management complexity must be minimized.',
        indent=True)

    _heading(doc, '2.3 Mandatory Access Control in Operating Systems', level=1)
    _body_para(doc,
        'The Bell-LaPadula model, introduced by David Bell and Leonard LaPadula in 1973 '
        'for the U.S. Department of Defense, established the theoretical foundation for '
        'Mandatory Access Control by defining subject-object access rules based on security '
        'labels and a lattice of classification levels. The Biba integrity model, published '
        'in 1977, addressed the dual concern of integrity rather than confidentiality. '
        'Modern operating system MAC implementations, including SELinux\'s Type Enforcement '
        'and Flask architecture (derived from the Mach-based Flask OS), implement '
        'generalized label-based access control that subsumes both models. '
        'SecureKernel\'s ACM implements a simplified but practically effective version of '
        'label-based MAC: subjects (processes) and objects (files, sockets) carry integer '
        'labels, and a policy rule table defines permitted (subject, object, operation) '
        'triples. This approach prioritizes deployment simplicity and runtime performance '
        'over the expressive power of a full type enforcement policy language.',
        indent=True)

    _heading(doc, '2.4 Kernel-Level Packet Filtering and Netfilter', level=1)
    _body_para(doc,
        'The Netfilter framework, introduced by Paul Russel and Harald Welte in Linux 2.4, '
        'provides a system of hooks within the kernel network stack at which external modules '
        'can inspect, modify, or drop network packets. The iptables and nftables tools use '
        'this framework to implement stateful packet filtering, network address translation, '
        'and packet mangling. Research by Salim, Khosravi, Kleen, and Kuznetsov into the '
        'netlink socket interface demonstrated the architectural advantages of in-kernel '
        'packet processing over userspace alternatives. SecureKernel\'s RBPF module takes '
        'a direct Netfilter hook approach rather than using the xtables framework, which '
        'eliminates the dependency on the iptables userspace toolchain and allows the '
        'filtering policy to be managed entirely through the /proc virtual filesystem with '
        'a simple text-based interface suitable for minimal embedded environments.',
        indent=True)

    _heading(doc, '2.5 Memory Management Optimization in Linux', level=1)
    _body_para(doc,
        'Gorman\'s comprehensive reference "Understanding the Linux Virtual Memory Manager" '
        '(2004) documents the buddy allocator, slab/SLUB allocator, page reclamation '
        'mechanisms, and swap subsystem that form the basis of Linux memory management. '
        'Subsequent work by Rik van Riel on the LRU-based page replacement algorithm '
        '(CLOCK-Pro inspiration) and by Mel Gorman on memory compaction (introduced in '
        'Linux 2.6.35) provided the foundation for proactive compaction, which SecureKernel\'s '
        'MMOA module exploits. The vm.swappiness tunable was introduced to allow system '
        'administrators to bias the kernel toward reclaiming page cache versus swapping '
        'anonymous pages; research by Arjan van de Ven demonstrated that values below 20 '
        'significantly reduce swap I/O on workloads with high temporal locality. '
        'SecureKernel\'s MMOA automates these well-understood tuning practices and adds a '
        'fragmentation monitoring loop that provides continuous visibility and automated '
        'remediation, a capability not present in the standard kernel without external tools.',
        indent=True)

    _heading(doc, '2.6 Embedded Linux and Kernel Minimization', level=1)
    _body_para(doc,
        'The Yocto Project, maintained by the Linux Foundation, provides a build system and '
        'reference distribution for generating customized embedded Linux images. The '
        'OpenEmbedded layer model allows fine-grained selection of packages and kernel '
        'configuration options, and Yocto\'s linux-yocto kernel includes patches for '
        'deterministic builds and embedded-specific optimizations. Buildroot, an alternative '
        'embedded Linux build system, provides a simpler Makefile-based approach to '
        'generating minimal root filesystems and kernel configurations. While both projects '
        'address kernel minimization as part of a broader embedded build system, neither '
        'provides the runtime security modules (MMOA, RBPF, ACM) that SecureKernel offers. '
        'SecureKernel\'s SCPA tool is conceptually aligned with the Yocto kernel '
        'configuration approach but is implemented as a standalone script that can be applied '
        'to any vanilla Linux 6.6 source tree without adopting the full Yocto or Buildroot '
        'build infrastructure.',
        indent=True)

    _heading(doc, '2.7 Kernel Address Space Layout Randomization', level=1)
    _body_para(doc,
        'KASLR, enabled by CONFIG_RANDOMIZE_BASE, randomizes the virtual address at which '
        'the kernel image is loaded at boot time, making it significantly harder for '
        'attackers to construct return-oriented programming (ROP) chains or kernel exploit '
        'payloads that rely on known kernel symbol addresses. Hund, Willems, and Holz '
        'demonstrated in 2013 that KASLR can be defeated through timing side channels '
        '(the "prefetch side-channel"), leading to subsequent enhancements including '
        'CONFIG_RANDOMIZE_MEMORY (which also randomizes the vmalloc and direct mapping '
        'regions) and CONFIG_PAGE_TABLE_ISOLATION (which mitigates the Meltdown '
        'microarchitectural vulnerability and also defends against some KASLR bypass '
        'techniques by isolating user-mode and kernel-mode page tables). SecureKernel\'s '
        'SCPA module enables all three options (RANDOMIZE_BASE, RANDOMIZE_MEMORY, and '
        'PAGE_TABLE_ISOLATION) as part of its security hardening profile, providing defense '
        'in depth against kernel address disclosure attacks.',
        indent=True)

    _heading(doc, '2.8 Control Flow Integrity in OS Kernels', level=1)
    _body_para(doc,
        'Control Flow Integrity (CFI), as formalized by Abadi, Budiu, Erlingsson, and '
        'Ligatti in 2005, provides a general defense against code-reuse attacks by '
        'restricting the set of valid control flow transfers at runtime. The Linux kernel\'s '
        'Clang CFI implementation (CONFIG_CFI_CLANG), introduced upstream in Linux 5.13 '
        'for ARM64 and extended to x86_64 in Linux 6.1, instruments indirect function calls '
        'with type-based checks that detect control-flow hijacking attempts. '
        'RETPOLINE (CONFIG_RETPOLINE), a software-based Spectre variant 2 mitigation, '
        'replaces indirect branch instructions with a return-trampoline sequence that '
        'prevents the CPU branch predictor from being trained to redirect execution to '
        'attacker-controlled code. SecureKernel\'s SCPA enables CONFIG_RETPOLINE as part '
        'of its security hardening profile. Full CFI (CONFIG_CFI_CLANG) requires the Clang '
        'compiler and is noted as a future enhancement in Chapter 9.',
        indent=True)

    # =========================================================
    # CHAPTER 3: SYSTEM ANALYSIS
    # =========================================================
    doc.add_page_break()
    _heading(doc, 'CHAPTER 3', level=0)
    _heading(doc, 'SYSTEM ANALYSIS', level=0)

    _heading(doc, '3.1 Existing System', level=1)
    _body_para(doc,
        'The existing system under analysis is a standard Linux distribution (such as '
        'Ubuntu 22.04, Debian 12, or Fedora 39) running an unmodified general-purpose '
        'kernel. Such distributions are designed for broad hardware compatibility and are '
        'the standard deployment choice for both desktop and server environments. They ship '
        'with a kernel configured to include support for thousands of hardware devices, all '
        'major filesystem types, a complete set of networking protocols, and extensive '
        'debugging and tracing infrastructure.',
        indent=True)
    _body_para(doc,
        'From a security perspective, existing systems rely on a multi-layered but '
        'fundamentally DAC-centric model. File system access is controlled by inode '
        'permission bits and access control lists. Network security is managed by iptables '
        'or nftables, both of which run as userspace processes and communicate with the '
        'kernel through the netlink socket interface. Mandatory Access Control, when '
        'deployed, is provided by SELinux (Red Hat ecosystem) or AppArmor (Debian/Ubuntu '
        'ecosystem), both of which require significant policy authoring expertise and '
        'introduce non-trivial boot-time overhead for policy loading.',
        indent=True)
    _body_para(doc,
        'From a performance and resource perspective, existing systems use default sysctl '
        'parameters tuned for workloads on machines with multiple gigabytes of RAM. The '
        'vm.swappiness=60 default means the kernel aggressively swaps anonymous pages even '
        'when significant page cache is available, leading to unnecessary swap I/O. The '
        'default min_free_kbytes is typically 1500-3000 KB, which is insufficient reserve '
        'for proactive reclamation on a 512 MB system. No proactive memory compaction is '
        'performed; compaction only occurs reactively when a high-order allocation fails.',
        indent=True)

    _heading(doc, '3.1.1 Disadvantages of Existing System', level=1)
    disadvantages = [
        ('Kernel Image Bloat',
         'The stock x86_64 bzImage measures approximately 14 MB and includes drivers for '
         'hardware not present on most deployment targets. Sound card drivers, Bluetooth '
         'stacks, FireWire controllers, and ATM networking modules contribute to the image '
         'size without providing any functional benefit on a headless network appliance.'),
        ('Slow Boot Time',
         'Initializing thousands of drivers and subsystems at boot extends the time-to-shell '
         'to approximately 3.8 seconds on QEMU, a significant delay for latency-sensitive '
         'IoT or edge devices that must resume operation rapidly after power cycles.'),
        ('Excessive Attack Surface',
         'Every compiled-in driver and subsystem is a potential exploit entry point. '
         'Historical Linux CVEs include vulnerabilities in the Bluetooth stack (BleedingTooth, '
         'CVE-2020-12351), the ext4 filesystem, the DCCP protocol, and numerous device drivers '
         '— code that has no business being present on a network-only appliance.'),
        ('DAC Bypassed by Root',
         'Standard Unix discretionary access control is entirely bypassed by processes '
         'running with UID 0 (root). Any privilege escalation vulnerability that grants an '
         'attacker root access renders all DAC-based access controls ineffective. Without '
         'MAC, a compromised root process has unrestricted access to all system resources.'),
        ('Userspace Firewall Dependency',
         'iptables and nftables require userspace processes, package installation, rule '
         'compilation, and service management. On a minimal embedded system these '
         'dependencies add complexity, increase the size of the root filesystem, and '
         'introduce additional attack surface through the userspace firewall toolchain.'),
        ('Suboptimal Memory Parameters',
         'Default sysctl values cause excessive swap I/O and sluggish memory reclamation '
         'on memory-constrained hardware. No mechanism exists in a stock kernel to '
         'automatically retune these parameters based on the available RAM at runtime.'),
        ('Memory Fragmentation',
         'The Linux buddy allocator does not perform proactive compaction. As the system '
         'runs, memory becomes fragmented and high-order allocations begin to fail, '
         'potentially triggering OOM kills of critical processes.'),
        ('Manual Kernel Configuration',
         'Generating a minimal, hardened kernel configuration requires detailed knowledge '
         'of hundreds of Kconfig options, their interdependencies, and their security '
         'implications. There is no automated tool in the standard kernel tree that produces '
         'a minimal-and-hardened configuration for a specified deployment profile.'),
        ('Complex MAC Deployment',
         'SELinux policy authoring requires specialized expertise, a policy compiler, and '
         'policy distribution infrastructure. AppArmor, while simpler, uses path-based '
         'matching that is susceptible to hardlink attacks and does not provide the same '
         'guarantees as label-based MAC. Both can be disabled at boot via a kernel parameter.'),
    ]
    for i, (title, desc) in enumerate(disadvantages, 1):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        p.paragraph_format.space_before = Pt(0)
        p.paragraph_format.space_after = Pt(4)
        p.paragraph_format.line_spacing = Pt(18)
        p.paragraph_format.first_line_indent = Inches(0)
        p.paragraph_format.left_indent = Inches(0.5)
        r1 = p.add_run(f'{i}. {title}: ')
        r1.font.name = 'Times New Roman'; r1.font.size = Pt(12); r1.bold = True
        r2 = p.add_run(desc)
        r2.font.name = 'Times New Roman'; r2.font.size = Pt(12)

    _heading(doc, '3.2 Proposed System', level=1)
    _body_para(doc,
        'SecureKernel is proposed as an integrated, in-kernel hardening and optimization '
        'framework that addresses all identified disadvantages of the existing system. The '
        'proposed system modifies the Linux 6.6.140 LTS kernel at both compile time and '
        'runtime through four purpose-built modules, each targeting a specific, orthogonal '
        'dimension of the security and performance problem.',
        indent=True)
    _body_para(doc,
        'The architectural principle of SecureKernel is that all security enforcement should '
        'occur at the kernel level, requiring no userspace processes, no external package '
        'dependencies, and no complex policy compilation infrastructure. Runtime management '
        'is provided through the /proc virtual filesystem, which is always present in any '
        'running Linux kernel and requires only basic shell access to use. This design '
        'philosophy makes SecureKernel immediately usable in the most minimal embedded '
        'environment with only a BusyBox shell.',
        indent=True)
    _body_para(doc,
        'Module 1 (SCPA) automates the generation of minimal, hardened kernel configurations '
        'for four deployment profiles (embedded, server, desktop, IoT). Module 2 (MMOA) '
        'automatically applies optimal sysctl parameters at boot and performs continuous '
        'fragmentation monitoring. Module 3 (RBPF) provides kernel-native packet filtering '
        'through Netfilter hooks. Module 4 (ACM) implements label-based MAC through the LSM '
        'framework. Together, these four modules create a cohesive security and optimization '
        'stack with measurable, verified benefits.',
        indent=True)

    _heading(doc, '3.2.1 Advantages of Proposed System', level=1)
    advantages = [
        ('Automated Kernel Minimization',
         'SCPA generates a profile-specific minimal kernel configuration automatically, '
         'eliminating the need for expert knowledge of hundreds of Kconfig options and '
         'removing approximately 55 percent of unnecessary code from the kernel image.'),
        ('Significantly Faster Boot Time',
         'By removing the initialization of thousands of unneeded subsystems, SecureKernel '
         'achieves approximately 61 percent faster boot time (1.5 seconds vs. 3.8 seconds '
         'on QEMU/KVM), critical for latency-sensitive embedded and IoT applications.'),
        ('Reduced Attack Surface',
         'Code that is not compiled into the kernel cannot be exploited. SCPA ensures that '
         'Bluetooth, sound, FireWire, legacy protocols, and debug infrastructure are '
         'physically absent from the deployed kernel binary.'),
        ('Mandatory Access Control for All Processes',
         'ACM enforces label-based MAC that applies to all processes including root, '
         'eliminating the fundamental DAC bypass vulnerability inherent in standard Unix '
         'permission models.'),
        ('Kernel-Native Packet Filtering',
         'RBPF provides packet filtering with zero userspace dependency. Rules are evaluated '
         'directly in the Netfilter hook path with approximately 2 percent throughput '
         'overhead and full SYN flood resilience.'),
        ('Proactive Memory Optimization',
         'MMOA automatically tunes sysctl parameters at boot and performs continuous '
         'fragmentation monitoring, eliminating OOM events that occurred during stress '
         'testing on the unmodified kernel.'),
        ('Simple Runtime Management',
         'All runtime configuration through /proc virtual files using standard shell '
         'commands. No package installation, policy compilation, or special tools required.'),
        ('License-Free and Open Source',
         'All SecureKernel components are licensed under GPL-2.0 and integrate directly '
         'into the mainline Linux kernel source tree. No commercial license or proprietary '
         'components are required.'),
    ]
    for i, (title, desc) in enumerate(advantages, 1):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        p.paragraph_format.space_before = Pt(0)
        p.paragraph_format.space_after = Pt(4)
        p.paragraph_format.line_spacing = Pt(18)
        p.paragraph_format.first_line_indent = Inches(0)
        p.paragraph_format.left_indent = Inches(0.5)
        r1 = p.add_run(f'{i}. {title}: ')
        r1.font.name = 'Times New Roman'; r1.font.size = Pt(12); r1.bold = True
        r2 = p.add_run(desc)
        r2.font.name = 'Times New Roman'; r2.font.size = Pt(12)

    # =========================================================
    # CHAPTER 4: SYSTEM SPECIFICATION
    # =========================================================
    doc.add_page_break()
    _heading(doc, 'CHAPTER 4', level=0)
    _heading(doc, 'SYSTEM SPECIFICATION', level=0)

    _heading(doc, '4.1 Hardware Requirements', level=1)
    _body_para(doc,
        'The hardware requirements for SecureKernel encompass both the build host system '
        'used to compile the kernel and the target deployment hardware. The build host must '
        'be a 64-bit x86 machine with sufficient RAM and storage to support the kernel '
        'compilation process, which involves compiling over one million lines of C source '
        'code. The QEMU test environment runs on the build host and simulates the target '
        'hardware. Table 4.1 specifies the hardware requirements.',
        indent=True)
    hw_data = [
        ('Processor', 'x86_64 compatible, 1 GHz, single core', 'Intel Core i5/i7 or AMD Ryzen, 2+ GHz, VT-x/AMD-V support, 4+ cores'),
        ('RAM (Build Host)', '4 GB', '16 GB (kernel compilation uses up to 8 GB with parallel jobs)'),
        ('RAM (QEMU Guest)', '256 MB minimum', '512 MB (representative of edge device)'),
        ('Storage', '20 GB free space', '50 GB+ (kernel source 1.3 GB, build artifacts ~5 GB, VM images)'),
        ('Network Interface', '100 Mbps Ethernet', 'Gigabit Ethernet (for RBPF throughput testing)'),
        ('Virtualization', 'QEMU/KVM capable CPU', 'Intel VT-x or AMD-V hardware virtualization support'),
        ('Display', 'Terminal (headless)', 'Not required (all operation via console/SSH)'),
    ]
    _add_table(doc,
               ['Component', 'Minimum Specification', 'Recommended Specification'],
               hw_data, col_widths=[3.5, 6, 7])
    _body_para(doc, 'Table 4.1: Hardware Requirements', indent=False,
               align=WD_ALIGN_PARAGRAPH.CENTER)

    _heading(doc, '4.2 Software Requirements', level=1)
    _body_para(doc,
        'SecureKernel requires a Linux host operating system for compilation and testing. '
        'The primary development and test environment was Ubuntu 22.04 LTS and Kali Linux '
        '2024.x, both of which provide current versions of all required build tools through '
        'their standard package managers. Table 4.2 lists all required software components '
        'with their versions and purposes.',
        indent=True)
    sw_data = [
        ('Linux Kernel Source', '6.6.140 LTS', 'Base kernel source tree for modification and integration of all four modules'),
        ('GCC (GNU C Compiler)', '12.x or higher', 'Primary C compiler for kernel and module source code compilation'),
        ('GNU Make', '4.3+', 'Build system for Makefile-driven kernel configuration and compilation'),
        ('GNU Bash', '5.x', 'Shell interpreter required for SCPA pruning script execution'),
        ('QEMU System Emulator', '7.x or higher', 'Full system emulation for kernel boot testing and performance benchmarking'),
        ('BusyBox', '1.36+', 'Minimal multi-call binary providing all initramfs userland utilities'),
        ('Python 3', '3.10+', 'Kernel .config patching automation and Kconfig/Makefile integration scripts'),
        ('Git', '2.x+', 'Source code version control and patch management'),
        ('Flex and Bison', 'Current', 'Lexer and parser generators required by kernel build system'),
        ('OpenSSL (libssl-dev)', '3.x', 'Cryptographic library required for kernel module signing support'),
        ('libelf-dev', 'Current', 'ELF library required for BTF and debug information generation'),
        ('dwarves (pahole)', 'Current', 'BTF type information extraction for BPF support'),
        ('cpio and gzip', 'Current', 'Initramfs packaging: cpio archive creation, gzip compression'),
        ('Host OS', 'Ubuntu 22.04 / Kali 2024', 'Linux host environment for build, test, and benchmarking operations'),
    ]
    _add_table(doc,
               ['Software', 'Version', 'Purpose'],
               sw_data, col_widths=[4, 2.5, 10])
    _body_para(doc, 'Table 4.2: Software Requirements', indent=False,
               align=WD_ALIGN_PARAGRAPH.CENTER)

    _body_para(doc,
        'Linux 6.6.140 LTS was selected as the base kernel because LTS releases receive '
        'long-term security maintenance (until December 2026 for the 6.6 series) and are '
        'specifically recommended for production and embedded deployments. GCC 12 is '
        'required as the minimum compiler version because several kernel security hardening '
        'options (including CONFIG_STACKPROTECTOR_STRONG and stack clash protection) require '
        'compiler-side support available only from GCC 4.9 onwards, with full feature '
        'support from GCC 11 and 12.',
        indent=True)
    _body_para(doc,
        'QEMU version 7.x is required for virtio device support and KVM acceleration, which '
        'are used to achieve near-native performance in the test environment. BusyBox 1.36 '
        'provides all the shell utilities (sh, cat, echo, ls, free, dmesg, and others) '
        'needed for the initramfs test environment without requiring a full Linux distribution '
        'to be installed in the guest. Python 3.10 is required for the f-string syntax and '
        'the regex module features used in the kernel configuration patching scripts.',
        indent=True)
