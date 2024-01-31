import re
import sys

def generate_link(title, existing_links):
    # Convert to lowercase and remove non-word characters
    link = re.sub(r'[^\w\s-]', '', title.lower())
    # Replace spaces and multiple hyphens with a single hyphen
    link = re.sub(r'[-\s]+', '-', link).strip('-')
    # Ensure the link is unique
    original_link = link
    count = 1
    while link in existing_links:
        link = f"{original_link}-{count}"
        count += 1
    existing_links.add(link)
    return link

def generate_toc(markdown_content):
    heading_pattern = r'## \[(.*?)\] (.*)'
    matches = re.findall(heading_pattern, markdown_content)
    toc = ["| ID | Title |", "| :--- | :--- |"]
    existing_links = set()
    for id, title in matches:
        link = generate_link(title, existing_links)
        toc.append(f"| {id} | [{title}](#{id.lower()}-{link}) |")
    return '\n'.join(toc)

def read_markdown_file(file_path):
    with open(file_path, 'r') as file:
        return file.read()

# Main execution
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python script.py <path_to_markdown_file>")
        sys.exit(1)

    markdown_file_path = sys.argv[1]
    try:
        markdown_content = read_markdown_file(markdown_file_path)
        toc = generate_toc(markdown_content)
        print(toc)
    except FileNotFoundError:
        print(f"Error: File not found - {markdown_file_path}")
    except Exception as e:
        print(f"Error: {e}")
